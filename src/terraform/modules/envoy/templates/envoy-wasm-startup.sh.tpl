#!/bin/bash
set -e

# Install Docker and required tools
apt-get update
apt-get install -y docker.io docker-compose curl

# Create Envoy config directory
mkdir -p /opt/envoy

# Download pre-built WASM filter from GCS
echo "Downloading WASM filter from GCS..."
gsutil cp gs://${gcs_bucket_name}/wasm/tenant-router.wasm /opt/envoy/tenant-router.wasm

# Verify WASM was downloaded
if [ ! -f "/opt/envoy/tenant-router.wasm" ]; then
    echo "ERROR: Failed to download WASM filter"
    exit 1
fi

echo "WASM filter downloaded successfully - v2"

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
  --log-driver=gcplogs \
  --log-opt gcp-log-cmd=true \
  --log-opt gcp-project=${project_id} \
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
%{ for shard_name, shard in shard_backends ~}
iptables -t nat -I OUTPUT 1 -p tcp -d ${shard.shard_alb_ip} -j RETURN
%{ endfor ~}

# Run Envoy
docker run -d \
  --name envoy \
  --network host \
  --restart always \
  --log-driver=gcplogs \
  --log-opt gcp-log-cmd=true \
  --log-opt gcp-project=${project_id} \
  -v /opt/envoy/envoy.yaml:/etc/envoy/envoy.yaml \
  -v /opt/envoy/tenant-router.wasm:/opt/envoy/tenant-router.wasm \
  envoyproxy/envoy:v1.28-latest \
  /usr/local/bin/envoy -c /etc/envoy/envoy.yaml