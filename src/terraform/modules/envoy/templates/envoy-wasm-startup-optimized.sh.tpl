#!/bin/bash
set -e

# Create Envoy config
cat > /opt/envoy/envoy.yaml << 'ENVOY_CONFIG'
${envoy_config}
ENVOY_CONFIG

# Configure iptables rules
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8000
iptables -t nat -A OUTPUT -p tcp --dport 80 ! -d 169.254.169.254 -j REDIRECT --to-port 8000

# Exclude shard ALB IPs from iptables redirect
%{ for shard_name, shard in shard_backends ~}
iptables -t nat -I OUTPUT 1 -p tcp -d ${shard.shard_alb_ip} -j RETURN
%{ endfor ~}

# Start containers (they're already pre-pulled)
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