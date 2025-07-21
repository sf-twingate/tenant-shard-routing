#!/bin/bash
set -e

# Install Docker and build tools
apt-get update
apt-get install -y docker.io docker-compose curl build-essential

# Install Rust (for building WASM)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "/root/.cargo/env"
/root/.cargo/bin/rustup target add wasm32-wasip1

# Create Envoy config directory
mkdir -p /opt/envoy

# Build WASM filter
cd /tmp
cat > Cargo.toml << 'CARGO_EOF'
${cargo_toml}
CARGO_EOF

mkdir -p src
cat > src/lib.rs << 'RUST_EOF'
${wasm_source}
RUST_EOF

# Build the WASM module
/root/.cargo/bin/cargo build --target wasm32-wasip1 --release
cp target/wasm32-wasip1/release/tenant_router.wasm /opt/envoy/tenant-router.wasm

# Create Envoy config
cat > /opt/envoy/envoy.yaml << 'ENVOY_CONFIG'
${envoy_config}
ENVOY_CONFIG

# Stop and remove any existing containers
docker stop envoy 2>/dev/null || true
docker rm envoy 2>/dev/null || true
docker stop gcs-proxy 2>/dev/null || true
docker rm gcs-proxy 2>/dev/null || true

# Configure Docker to authenticate with GCR
gcloud auth configure-docker gcr.io

# Run GCS proxy container
docker run -d \
  --name gcs-proxy \
  --restart always \
  --network host \
  -e PORT=8080 \
  -e RUST_LOG=info \
  gcr.io/${project_id}/gcs-proxy:latest

# Wait for GCS proxy to be ready
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null; then
        echo "GCS proxy is ready"
        break
    fi
    echo "Waiting for GCS proxy to start..."
    sleep 2
done

# Add iptables rules to redirect port 80 to 8000 (excluding metadata service and shard ALBs)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8000
iptables -t nat -A OUTPUT -p tcp --dport 80 ! -d 169.254.169.254 -j REDIRECT --to-port 8000

# Exclude shard ALB IPs from iptables redirect
%{ for shard_name in shard_names ~}
iptables -t nat -I OUTPUT 1 -p tcp -d ${shard_backends[shard_name].shard_alb_ip} -j RETURN
%{ endfor ~}

# Run Envoy
docker run -d \
  --name envoy \
  --network host \
  --restart always \
  -v /opt/envoy/envoy.yaml:/etc/envoy/envoy.yaml \
  -v /opt/envoy/tenant-router.wasm:/opt/envoy/tenant-router.wasm \
  envoyproxy/envoy:v1.28-latest \
  /usr/local/bin/envoy -c /etc/envoy/envoy.yaml