#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get project ID
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}No project ID found. Please run 'gcloud config set project PROJECT_ID'${NC}"
    exit 1
fi

# Get GCS bucket name from Terraform
cd "$PROJECT_ROOT/terraform"
GCS_BUCKET=$(terraform output -raw gcs_bucket_name 2>/dev/null || echo "")
if [ -z "$GCS_BUCKET" ]; then
    echo -e "${YELLOW}Warning: Could not get GCS bucket name from Terraform${NC}"
    GCS_BUCKET="${PROJECT_ID}-tenant-shard-mapping"
fi

echo -e "${YELLOW}Building custom Envoy VM image...${NC}"
echo "Project ID: $PROJECT_ID"
echo "GCS Bucket: $GCS_BUCKET"

# Ensure required APIs are enabled
echo -e "${YELLOW}Checking required APIs...${NC}"
REQUIRED_APIS="compute.googleapis.com iap.googleapis.com"
for API in $REQUIRED_APIS; do
    if ! gcloud services list --enabled --filter="name:$API" --format="value(name)" | grep -q "$API"; then
        echo "Enabling $API..."
        gcloud services enable "$API"
    fi
done

# Ensure IAP firewall rule exists
echo -e "${YELLOW}Checking IAP firewall rule...${NC}"
if ! gcloud compute firewall-rules describe allow-iap-ingress &>/dev/null; then
    echo "Creating IAP firewall rule..."
    gcloud compute firewall-rules create allow-iap-ingress \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --quiet
fi

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    echo -e "${YELLOW}Packer is not installed. Installing Packer...${NC}"
    
    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Map architecture names
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    
    # Get latest Packer version
    PACKER_VERSION=$(curl -s https://api.github.com/repos/hashicorp/packer/releases/latest | grep -oE '"tag_name": "v[0-9]+\.[0-9]+\.[0-9]+"' | cut -d'"' -f4 | sed 's/v//')
    
    if [ -z "$PACKER_VERSION" ]; then
        echo -e "${RED}Failed to get latest Packer version${NC}"
        exit 1
    fi
    
    # Download and install Packer
    PACKER_URL="https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_${OS}_${ARCH}.zip"
    echo "Downloading Packer ${PACKER_VERSION} for ${OS}/${ARCH}..."
    
    # Create temp directory
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    # Download Packer
    if ! curl -sL "$PACKER_URL" -o packer.zip; then
        echo -e "${RED}Failed to download Packer${NC}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    
    # Unzip Packer
    unzip -q packer.zip
    
    # Install Packer
    if [ "$OS" = "darwin" ]; then
        # macOS - install to /usr/local/bin
        if [ -w /usr/local/bin ]; then
            mv packer /usr/local/bin/
        else
            echo -e "${YELLOW}Installing Packer requires sudo access${NC}"
            sudo mv packer /usr/local/bin/
        fi
    else
        # Linux - install to /usr/local/bin
        if [ -w /usr/local/bin ]; then
            mv packer /usr/local/bin/
        else
            echo -e "${YELLOW}Installing Packer requires sudo access${NC}"
            sudo mv packer /usr/local/bin/
        fi
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    
    # Verify installation
    if command -v packer &> /dev/null; then
        echo -e "${GREEN}✓ Packer ${PACKER_VERSION} installed successfully!${NC}"
    else
        echo -e "${RED}Failed to install Packer${NC}"
        exit 1
    fi
fi

# Initialize Packer (only for WASM image)
cd "$PROJECT_ROOT/packer"
packer init envoy-wasm-image.pkr.hcl

# Build the image
echo -e "${YELLOW}Building WASM-optimized image (this will take 5-10 minutes)...${NC}"
packer build \
    -var "project_id=$PROJECT_ID" \
    envoy-wasm-image.pkr.hcl

echo -e "${GREEN}✓ Custom Envoy WASM image built successfully!${NC}"
echo ""
echo "To use the new image, update the Terraform configuration to use:"
echo "  source_image = \"envoy-wasm-optimized\""
echo "  source_image_project = \"$PROJECT_ID\""
echo "  use_lua_filter = false"