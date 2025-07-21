#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

echo "🚀 Deploying Tenant Routing WASM Infrastructure"

# Check if terraform.tfvars exists
if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]; then
    echo "Error: terraform/terraform.tfvars not found"
    echo "Please copy terraform/terraform.tfvars.example and configure it"
    exit 1
fi

# Deploy infrastructure first
echo "🏗️  Deploying infrastructure with Terraform..."
cd "$PROJECT_ROOT/terraform"
terraform init
terraform apply -auto-approve

# Build and upload tenant lookup service after infrastructure is deployed
echo "📦 Building tenant lookup service..."
"$SCRIPT_DIR/build-tenant-lookup.sh"

# Build WASM locally if not using Lua mode
echo "📦 Building WASM filter..."
cd "$PROJECT_ROOT/wasm-filter"
if [ -f "./build.sh" ]; then
    ./build.sh
else
    echo "⚠️  WASM build script not found, WASM will be built on Envoy instance"
fi

# Get IPs
ENVOY_IP=$(terraform output -raw envoy_ip)
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
"$SCRIPT_DIR/test-deployment.sh" "$ENVOY_IP" "$LB_IP"

# Display helpful information
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "📊 Infrastructure Details:"
cd "$PROJECT_ROOT/terraform"
echo "Load Balancer IP: $(terraform output -raw load_balancer_ip 2>/dev/null || echo $LB_IP)"
echo "GCS Bucket: $(terraform output -raw gcs_bucket 2>/dev/null || echo 'N/A')"
echo ""
echo "🧪 To test the deployment:"
echo "  curl -H 'Host: beamreach.example.com' http://$LB_IP/"
echo "  curl -H 'Host: sfco.example.com' http://$LB_IP/"
echo ""
echo "🏗️  Architecture flow:"
terraform output architecture_flow 2>/dev/null || echo "Architecture flow output not available"