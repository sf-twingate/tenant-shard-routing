#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

echo "🧹 Cleaning up Tenant Routing Infrastructure"
echo "⚠️  This will destroy all resources created by Terraform"
echo ""
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

cd "$PROJECT_ROOT/terraform"

# Get project ID
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-tenant-shard-mapping"

# Check if bucket exists and empty it
if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    echo "📦 Emptying bucket gs://${BUCKET_NAME}..."
    gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
fi

# Clean up orphaned resources that might exist outside of Terraform state
echo "🧹 Cleaning up orphaned resources..."

# Get the name prefix from terraform variables
NAME_PREFIX=$(terraform output -raw name_prefix 2>/dev/null || echo "tenant-routing")

# Delete resources in dependency order (reverse of creation order)
# 1. First delete forwarding rules (depends on target proxies)
echo "  Looking for forwarding rules with prefix: $NAME_PREFIX or shard..."
for rule in $(gcloud compute forwarding-rules list --global --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting forwarding rule $rule..."
    gcloud compute forwarding-rules delete "$rule" --global --quiet
done

# 2. Delete target HTTP proxies (depends on URL maps)
echo "  Looking for HTTP proxies with prefix: $NAME_PREFIX or shard..."
for proxy in $(gcloud compute target-http-proxies list --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting HTTP proxy $proxy..."
    gcloud compute target-http-proxies delete "$proxy" --quiet
done

# 3. Delete URL maps (depends on backend services)
echo "  Looking for URL maps with prefix: $NAME_PREFIX or shard..."
for urlmap in $(gcloud compute url-maps list --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting URL map $urlmap..."
    gcloud compute url-maps delete "$urlmap" --quiet
done

# 4. Delete backend services (depends on NEGs/instance groups)
echo "  Looking for backend services with prefix: $NAME_PREFIX or shard..."
for bs in $(gcloud compute backend-services list --global --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting backend service $bs..."
    gcloud compute backend-services delete "$bs" --global --quiet
done

# 5. Delete NEGs (now safe to delete)
echo "  Looking for network endpoint groups with prefix: $NAME_PREFIX or shard..."
for neg in $(gcloud compute network-endpoint-groups list --global --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting network endpoint group $neg..."
    gcloud compute network-endpoint-groups delete "$neg" --global --quiet
done

# 6. Delete global addresses
echo "  Looking for global addresses with prefix: $NAME_PREFIX or shard..."
for addr in $(gcloud compute addresses list --global --filter="name:($NAME_PREFIX-* OR name:shard*)" --format="value(name)"); do
    echo "  Deleting global address $addr..."
    gcloud compute addresses delete "$addr" --global --quiet
done

# Delete compute instances with prefix
echo "  Looking for instances with prefix: $NAME_PREFIX or shard..."
for instance in $(gcloud compute instances list --filter="name:($NAME_PREFIX-* OR name:shard*) AND zone:us-central1-a" --format="value(name)"); do
    echo "  Deleting instance $instance..."
    gcloud compute instances delete "$instance" --zone=us-central1-a --quiet
done

# Delete instance groups with prefix
echo "  Looking for instance groups with prefix: $NAME_PREFIX..."
for ig in $(gcloud compute instance-groups list --filter="name:($NAME_PREFIX-*) AND zone:us-central1-a" --format="value(name)"); do
    echo "  Deleting instance group $ig..."
    gcloud compute instance-groups delete "$ig" --zone=us-central1-a --quiet
done

# Delete health checks with prefix
echo "  Looking for health checks with prefix: $NAME_PREFIX..."
for hc in $(gcloud compute health-checks list --filter="name:($NAME_PREFIX-*)" --format="value(name)"); do
    echo "  Deleting health check $hc..."
    gcloud compute health-checks delete "$hc" --quiet
done

# Delete firewall rules with prefix
echo "  Looking for firewall rules with prefix: $NAME_PREFIX..."
for fw in $(gcloud compute firewall-rules list --filter="name:(*$NAME_PREFIX*)" --format="value(name)"); do
    echo "  Deleting firewall rule $fw..."
    gcloud compute firewall-rules delete "$fw" --quiet
done

terraform destroy -auto-approve

echo "✅ Cleanup complete!"