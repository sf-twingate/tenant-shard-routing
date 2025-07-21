#!/bin/bash
# Script to set up tenant mappings for testing

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get bucket name from Terraform
cd "$SCRIPT_DIR/../terraform"
BUCKET=$(terraform output -raw gcs_bucket 2>/dev/null)

if [ -z "$BUCKET" ]; then
    echo "Error: Could not get tenant mappings bucket from Terraform"
    echo "Make sure to run 'terraform apply' first"
    exit 1
fi

echo "Setting up test tenant mappings in bucket: $BUCKET"

# Create some test mappings
echo "shard1" | gsutil cp - "gs://$BUCKET/default/shard"
echo "shard1" | gsutil cp - "gs://$BUCKET/corp/shard"
echo "shard1" | gsutil cp - "gs://$BUCKET/beamreach/shard"
echo "shard2" | gsutil cp - "gs://$BUCKET/sfco/shard"
echo "shard2" | gsutil cp - "gs://$BUCKET/foo/shard"

echo ""
echo "Test mappings created:"
echo "  default → shard1"
echo "  corp → shard1"
echo "  beamreach → shard1"
echo "  sfco → shard2"
echo "  foo → shard2"

echo ""
echo "To test, use these hostnames:"
echo "  beamreach.example.com"
echo "  sfco.example.com"
echo "  corp.example.com"
echo "  foo.example.com"