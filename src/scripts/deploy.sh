#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

echo "🚀 Deploying Tenant Routing Infrastructure"

# Check if terraform.tfvars exists
if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    echo "Error: terraform/terraform.tfvars not found"
    echo "Please copy terraform/terraform.tfvars.example and configure it"
    exit 1
fi

# Ask for deployment type
echo ""
echo "Select deployment type:"
echo "1) Single Instance (default) - Deploy Envoy in one region"
echo "2) Global - Deploy Envoy across multiple regions worldwide"
echo ""
read -p "Enter choice [1-2] (default: 1): " DEPLOYMENT_TYPE
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-1}

if [ "$DEPLOYMENT_TYPE" = "2" ]; then
    echo "🌍 Deploying global multi-region infrastructure..."
    USE_GLOBAL=true
else
    echo "📍 Deploying single-region infrastructure..."
    USE_GLOBAL=false
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project)

# Check if we're using optimized image from terraform.tfvars
USE_OPTIMIZED_IMAGE=$(grep -E "^use_optimized_image\s*=" "$PROJECT_ROOT/terraform/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*//; s/[[:space:]]*//g' || echo "false")
# Check if we're using Lua filter
USE_LUA_FILTER=$(grep -E "^use_lua_filter\s*=" "$PROJECT_ROOT/terraform/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*//; s/[[:space:]]*//g' || echo "false")

# If using optimized image, check if it exists and build if needed
if [ "$USE_OPTIMIZED_IMAGE" = "true" ]; then
    echo "⚡ Checking for optimized image..."
    
    # Determine which image family to check based on filter type
    if [ "$USE_LUA_FILTER" = "true" ]; then
        IMAGE_FAMILY="envoy-lua-optimized"
        BUILD_SCRIPT="build-envoy-lua-image.sh"
    else
        IMAGE_FAMILY="envoy-wasm-optimized"
        BUILD_SCRIPT="build-envoy-wasm-image.sh"
    fi
    
    # Check if the image exists
    IMAGE_EXISTS=$(gcloud compute images list --filter="family:$IMAGE_FAMILY" --format="value(name)" | head -1)
    
    if [ -z "$IMAGE_EXISTS" ]; then
        echo "📦 Optimized image not found. Building it now (this will take ~10 minutes)..."
        if [ -f "$SCRIPT_DIR/$BUILD_SCRIPT" ]; then
            "$SCRIPT_DIR/$BUILD_SCRIPT"
        else
            echo "❌ Error: $BUILD_SCRIPT not found"
            exit 1
        fi
    else
        echo "✅ Found optimized image: $IMAGE_EXISTS"
    fi
    
    if [ "$USE_LUA_FILTER" = "true" ]; then
        echo "⚡ Using Lua-optimized image with pre-built tenant lookup service"
    else
        echo "⚡ Using WASM-optimized image with pre-built WASM filter"
    fi
elif [ "$USE_LUA_FILTER" != "true" ] && [ -f "$PROJECT_ROOT/wasm-filter/build.sh" ]; then
    # Build WASM locally if not using optimized image and not using Lua
    echo "📦 Building WASM filter locally..."
    cd "$PROJECT_ROOT/wasm-filter"
    ./build.sh
    cd "$PROJECT_ROOT"
fi

# Deploy infrastructure
echo "🏗️  Deploying infrastructure with Terraform..."
cd "$PROJECT_ROOT/terraform"
terraform init

# First, create just the GCS bucket
echo "🪣 Creating GCS bucket first..."
terraform apply -auto-approve -target=module.gcs -var="use_global_deployment=$USE_GLOBAL"

# Get the bucket name from terraform output
GCS_BUCKET=$(terraform output -raw gcs_bucket 2>/dev/null || echo "")
if [ -z "$GCS_BUCKET" ]; then
    echo "❌ Failed to get GCS bucket name from terraform"
    exit 1
fi

# Upload WASM to the GCS bucket before creating instances (only if not using optimized image and using WASM)
if [ "$USE_LUA_FILTER" != "true" ]; then
    if [ "$USE_OPTIMIZED_IMAGE" != "true" ]; then
        if [ -f "$PROJECT_ROOT/tenant-router.wasm" ]; then
            echo "📤 Uploading WASM filter to GCS bucket: $GCS_BUCKET..."
            gsutil cp "$PROJECT_ROOT/tenant-router.wasm" "gs://${GCS_BUCKET}/wasm/tenant-router.wasm"
            echo "✅ WASM filter uploaded to gs://${GCS_BUCKET}/wasm/tenant-router.wasm"
        else
            echo "⚠️ WASM file not found at $PROJECT_ROOT/tenant-router.wasm"
        fi
    else
        echo "⚡ Using WASM-optimized image - WASM is pre-built in the image"
    fi
else
    echo "🌐 Using Lua filter - no WASM upload needed"
fi

# Now deploy the rest of the infrastructure
echo "🚀 Deploying remaining infrastructure..."
terraform apply -auto-approve -var="use_global_deployment=$USE_GLOBAL"

# Build and upload tenant lookup service after infrastructure is deployed
echo "📦 Building tenant lookup service..."
"$SCRIPT_DIR/build-tenant-lookup.sh"

# Return to terraform directory to get outputs
cd "$PROJECT_ROOT/terraform"

# Get IPs
if [ "$USE_GLOBAL" = true ]; then
    # For global deployment, we don't have a single Envoy IP
    ENVOY_IP="Global (multiple regions)"
    echo "🌍 Global deployment complete. Envoy instances deployed in:"
    echo "   - US Central (us-central1)"
    echo "   - Europe West (europe-west1)"
    echo "   - Asia Southeast (asia-southeast1)"
    echo "   - US East (us-east1)"
    echo "   - Australia (australia-southeast1)"
else
    ENVOY_IP=$(terraform output -raw envoy_ip 2>/dev/null || echo "N/A")
fi
LB_IP=$(terraform output -raw load_balancer_ip)

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📍 Envoy IP: $ENVOY_IP"
echo "📍 Load Balancer IP: $LB_IP"
echo ""
echo "🔄 Waiting for services to be ready (60s)..."
sleep 60

# Setup test tenant mappings
echo ""
echo "🔧 Setting up test tenant mappings..."
"$SCRIPT_DIR/setup-test-mappings.sh"

# Run tests
echo ""
echo "🧪 Running tests..."
if [ "$USE_GLOBAL" = true ]; then
    # For global deployment, skip Envoy IP parameter
    "$SCRIPT_DIR/test-deployment.sh" "" "$LB_IP"
else
    "$SCRIPT_DIR/test-deployment.sh" "$ENVOY_IP" "$LB_IP"
fi

# Display helpful information
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "📊 Infrastructure Details:"
cd "$PROJECT_ROOT/terraform"
echo "Load Balancer IP: $(terraform output -raw load_balancer_ip 2>/dev/null || echo $LB_IP)"
echo "GCS Bucket: $(terraform output -raw gcs_bucket 2>/dev/null || echo 'N/A')"

if [ "$USE_GLOBAL" = true ]; then
    echo ""
    echo "🌍 Global Deployment Details:"
    echo "   - Regions: US Central, Europe West, Asia Southeast, US East, Australia"
    echo "   - Auto-scaling: 2-10 instances per region"
    echo "   - Cloud CDN: Enabled"
    echo "   - Cloud Armor DDoS Protection: Enabled"
    echo "   - Anycast IP routes to nearest Envoy cluster"
fi

echo ""
echo "🧪 To test the deployment:"
echo "  curl -H 'Host: beamreach.example.com' http://$LB_IP/"
echo "  curl -H 'Host: sfco.example.com' http://$LB_IP/"
echo ""
echo "🏗️  Architecture flow:"
terraform output architecture_flow 2>/dev/null || echo "Architecture flow output not available"