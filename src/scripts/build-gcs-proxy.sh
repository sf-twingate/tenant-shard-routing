#!/bin/bash
set -e

# Build the GCS proxy and push to container registry

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

echo -e "${YELLOW}Building GCS proxy service...${NC}"

# Navigate to the GCS proxy directory
cd "$PROJECT_ROOT/gcs-proxy"

# Get git SHA for tagging
GIT_SHA=$(git rev-parse --short HEAD)

# Build using Docker
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t gcs-proxy -f Dockerfile --platform=linux/amd64 .

# Tag for GCR with both latest and git SHA
GCR_IMAGE_LATEST="gcr.io/${PROJECT_ID}/gcs-proxy:latest"
GCR_IMAGE_SHA="gcr.io/${PROJECT_ID}/gcs-proxy:${GIT_SHA}"
docker tag gcs-proxy "$GCR_IMAGE_LATEST"
docker tag gcs-proxy "$GCR_IMAGE_SHA"

# Push to GCR
echo -e "${YELLOW}Pushing to Google Container Registry...${NC}"
docker push "$GCR_IMAGE_LATEST"
docker push "$GCR_IMAGE_SHA"

echo -e "${GREEN}✓ GCS proxy built and pushed to ${GCR_IMAGE_LATEST} and ${GCR_IMAGE_SHA}${NC}"