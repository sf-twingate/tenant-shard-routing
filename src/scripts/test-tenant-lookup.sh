#!/bin/bash
set -e

# Test the tenant lookup service locally

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Testing Tenant Lookup Service Locally${NC}"

# Navigate to the tenant lookup service directory
cd "$PROJECT_ROOT/tenant-lookup-service"

# Build and run in Docker
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t tenant-lookup-test .

# Get GCS bucket name from Terraform
cd "$PROJECT_ROOT/terraform"
BUCKET_NAME=$(terraform output -raw gcs_bucket 2>/dev/null || echo "")

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}Using default test bucket name${NC}"
    BUCKET_NAME="test-tenant-routing-data"
fi

# Run the service in background
echo -e "${YELLOW}Starting tenant lookup service...${NC}"
docker run -d --name tenant-lookup-test \
    -p 8080:8080 \
    -e GCS_BUCKET="$BUCKET_NAME" \
    -e DEFAULT_SHARD="shard1" \
    -e RUST_LOG="info" \
    tenant-lookup-test

# Wait for service to start
sleep 3

# Test health endpoint
echo -e "${YELLOW}Testing health endpoint...${NC}"
if curl -s http://localhost:8080/health | grep -q "OK"; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    docker logs tenant-lookup-test
    docker stop tenant-lookup-test
    docker rm tenant-lookup-test
    exit 1
fi

# Test lookup endpoint
echo -e "${YELLOW}Testing lookup endpoint...${NC}"
RESPONSE=$(curl -s "http://localhost:8080/lookup?host=tenant1.example.com")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"shard"'; then
    echo -e "${GREEN}✓ Lookup endpoint returned valid response${NC}"
else
    echo -e "${RED}✗ Lookup endpoint failed${NC}"
    docker logs tenant-lookup-test
fi

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
docker stop tenant-lookup-test
docker rm tenant-lookup-test

echo -e "${GREEN}✓ Tests complete${NC}"