#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🗺️  Tenant Shard Mappings${NC}"
echo ""

# Get GCS bucket name from Terraform
cd "$PROJECT_ROOT/terraform" 2>/dev/null || {
    echo -e "${RED}Error: terraform directory not found${NC}"
    exit 1
}

# Try to get bucket name from terraform output
GCS_BUCKET=$(terraform output -raw gcs_bucket_name 2>/dev/null || echo "")

# If terraform output fails, try to get from tfvars
if [ -z "$GCS_BUCKET" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$PROJECT_ID" ]; then
        GCS_BUCKET="${PROJECT_ID}-tenant-shard-mapping"
        echo -e "${YELLOW}Note: Using default bucket name: $GCS_BUCKET${NC}"
    else
        echo -e "${RED}Error: Could not determine GCS bucket name${NC}"
        echo "Please ensure terraform is initialized or gcloud project is set"
        exit 1
    fi
fi

echo -e "${GREEN}📦 GCS Bucket: ${NC}$GCS_BUCKET"
echo ""

# Check if bucket exists
if ! gsutil ls -b "gs://$GCS_BUCKET" &>/dev/null; then
    echo -e "${RED}Error: Bucket gs://$GCS_BUCKET does not exist${NC}"
    exit 1
fi

# List all tenant directories
echo -e "${BLUE}📁 Tenant Mappings:${NC}"
TENANT_DIRS=$(gsutil ls "gs://$GCS_BUCKET/" 2>/dev/null | grep -E "/$" | grep -v "wasm/" || echo "")

if [ -z "$TENANT_DIRS" ]; then
    echo -e "${YELLOW}No tenant mappings found in gs://$GCS_BUCKET/${NC}"
    echo ""
    echo "To add tenant mappings, use:"
    echo "  ./setup-test-mappings.sh"
    exit 0
fi

# Display each mapping
echo "$TENANT_DIRS" | while read -r dir; do
    if [ -n "$dir" ] && [[ "$dir" != *"/wasm/"* ]]; then
        # Extract tenant name from directory path
        TENANT=$(basename "$dir" /)
        
        # Check if shard file exists
        SHARD_FILE="${dir}shard"
        SHARD=$(gsutil cat "$SHARD_FILE" 2>/dev/null | tr -d '\n' || echo "")
        
        if [ -n "$SHARD" ]; then
            echo ""
            echo -e "${GREEN}📋 Tenant: ${YELLOW}$TENANT${NC}"
            echo "  ├─ Domain: $TENANT.example.com"
            echo "  └─ Shard: $SHARD"
        fi
    fi
done

echo ""
echo -e "${BLUE}📊 Summary:${NC}"

# Count total mappings and shards
TOTAL_MAPPINGS=0

# Process all tenant directories to count mappings and shards
echo "$TENANT_DIRS" | while read -r dir; do
    if [ -n "$dir" ] && [[ "$dir" != *"/wasm/"* ]]; then
        SHARD_FILE="${dir}shard"
        SHARD=$(gsutil cat "$SHARD_FILE" 2>/dev/null | tr -d '\n' || echo "")
        if [ -n "$SHARD" ]; then
            echo "$SHARD"
        fi
    fi
done > /tmp/shards_$$.txt

TOTAL_MAPPINGS=$(cat /tmp/shards_$$.txt | wc -l | tr -d ' ')
echo "  Total tenant mappings: $TOTAL_MAPPINGS"

# Count mappings per shard
echo ""
echo -e "${BLUE}🎯 Shard Distribution:${NC}"
cat /tmp/shards_$$.txt | sort | uniq -c | while read -r count shard; do
    echo "  ├─ $shard: $count tenants"
done

# Clean up
rm -f /tmp/shards_$$.txt

echo ""
echo -e "${GREEN}✅ Done!${NC}"
echo ""
echo "To add or modify mappings:"
echo "  echo 'SHARD_NAME' | gsutil cp - gs://$GCS_BUCKET/TENANT_NAME/shard"
echo ""
echo "Example:"
echo "  echo 'us-shard1' | gsutil cp - gs://$GCS_BUCKET/acme-corp/shard"