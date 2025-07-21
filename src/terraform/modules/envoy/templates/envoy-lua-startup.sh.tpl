#!/bin/bash
set -e

# Install Docker and required tools
apt-get update
apt-get install -y docker.io docker-compose wget unzip

# Create directory for Envoy config
mkdir -p /opt/envoy

# Configure Docker to authenticate with GCR
gcloud auth configure-docker gcr.io

# Run tenant lookup service as a container
docker run -d \
  --name tenant-lookup \
  --restart always \
  --network host \
  --log-driver=gcplogs \
  --log-opt gcp-log-cmd=true \
  --log-opt gcp-project=${project_id} \
  -e GCS_BUCKET=${gcs_bucket_name} \
  -e DEFAULT_SHARD=${default_shard} \
  -e CACHE_TTL=300 \
  -e PORT=8080 \
  -e RUST_LOG=info \
  gcr.io/${project_id}/tenant-lookup:latest

# Wait for tenant lookup service to be ready
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null; then
        echo "Tenant lookup service is ready"
        break
    fi
    echo "Waiting for tenant lookup service to start..."
    sleep 2
done

# Create Envoy config
cat > /opt/envoy/envoy.yaml << 'ENVOY_CONFIG'
${envoy_config}
ENVOY_CONFIG

# Add iptables rules to redirect port 80 to 8000 (excluding metadata service and shard ALBs)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8000
iptables -t nat -A OUTPUT -p tcp --dport 80 ! -d 169.254.169.254 -j REDIRECT --to-port 8000

# Exclude shard ALB IPs from iptables redirect
%{ for shard_name in shard_names ~}
iptables -t nat -I OUTPUT 1 -p tcp -d ${shard_backends[shard_name].shard_alb_ip} -j RETURN
%{ endfor ~}

# Run Envoy with Lua support
docker run -d \
  --name envoy \
  --network host \
  --restart always \
  --log-driver=gcplogs \
  --log-opt gcp-log-cmd=true \
  --log-opt gcp-project=${project_id} \
  -v /opt/envoy/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.28-latest \
  /usr/local/bin/envoy -c /etc/envoy/envoy.yaml