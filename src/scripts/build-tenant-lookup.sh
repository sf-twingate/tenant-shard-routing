#!/bin/bash
set -e

# Build the Rust tenant lookup service and push to container registry

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

echo -e "${YELLOW}Building Rust tenant lookup service...${NC}"

# Navigate to the parent directory to have access to both tenant-lookup-service and tenant-routing-core
cd "$PROJECT_ROOT"

# Get git SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD)

# Build using Docker - use the parent directory as context
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t tenant-lookup-service -f tenant-lookup-service/Dockerfile --platform=linux/amd64 .

# Tag for GCR with both latest and git SHA
GCR_IMAGE_LATEST="gcr.io/${PROJECT_ID}/tenant-lookup-service:latest"
GCR_IMAGE_SHA="gcr.io/${PROJECT_ID}/tenant-lookup-service:${GIT_SHA}"
docker tag tenant-lookup-service "$GCR_IMAGE_LATEST"
docker tag tenant-lookup-service "$GCR_IMAGE_SHA"

# Push to GCR
echo -e "${YELLOW}Pushing to Google Container Registry...${NC}"
docker push "$GCR_IMAGE_LATEST"
docker push "$GCR_IMAGE_SHA"

echo -e "${GREEN}✓ Tenant lookup service built and pushed to ${GCR_IMAGE_LATEST} and ${GCR_IMAGE_SHA}${NC}"