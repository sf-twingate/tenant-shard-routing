#!/bin/bash
set -e

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get GCS bucket name
cd "$PROJECT_ROOT/terraform" 2>/dev/null || true
GCS_BUCKET=$(terraform output -raw gcs_bucket_name 2>/dev/null || echo "")

if [ -z "$GCS_BUCKET" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$PROJECT_ID" ]; then
        GCS_BUCKET="${PROJECT_ID}-tenant-shard-mapping"
    fi
fi

if [ -z "$GCS_BUCKET" ]; then
    exit 0
fi

# Check if bucket exists
if ! gsutil ls -b "gs://$GCS_BUCKET" &>/dev/null; then
    exit 0
fi

echo "📋 Tenant → Shard Mappings:"

# List all tenant directories and their shards
gsutil ls "gs://$GCS_BUCKET/" 2>/dev/null | grep -E "/$" | grep -v "wasm/" | while read -r dir; do
    if [ -n "$dir" ]; then
        TENANT=$(basename "$dir" /)
        SHARD=$(gsutil cat "${dir}shard" 2>/dev/null | tr -d '\n' || echo "")
        if [ -n "$SHARD" ]; then
            printf "  %-15s → %s\n" "$TENANT" "$SHARD"
        fi
    fi
done

echo ""