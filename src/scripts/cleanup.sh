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

# Try to get bucket name from terraform output first
BUCKET_NAME=$(terraform output -raw gcs_bucket 2>/dev/null | grep -v "Warning:" | grep -v "│" | head -1)
if [ -z "$BUCKET_NAME" ] || [[ "$BUCKET_NAME" == *"╷"* ]]; then
    BUCKET_NAME="${PROJECT_ID}-tenant-shard-mapping"
fi

# Check if bucket exists and empty it
if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    echo "📦 Emptying bucket gs://${BUCKET_NAME}..."
    gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
else
    echo "📦 Bucket gs://${BUCKET_NAME} not found or already deleted"
fi

# Run terraform destroy to handle dependencies properly
echo "🏗️  Running terraform destroy to clean up managed resources..."
terraform destroy -auto-approve

# Clean up orphaned resources that might exist outside of Terraform state
echo "🧹 Cleaning up orphaned resources that may have been missed..."

# Get the name prefix from terraform variables
# If terraform output fails, use default prefix
NAME_PREFIX=$(terraform output -raw name_prefix 2>/dev/null | grep -v "Warning:" | grep -v "│" | head -1)
if [ -z "$NAME_PREFIX" ] || [[ "$NAME_PREFIX" == *"╷"* ]]; then
    NAME_PREFIX="tenant-routing"
fi
echo "Using name prefix: $NAME_PREFIX"

# Delete resources in dependency order (reverse of creation order)
# 1. First delete forwarding rules (depends on target proxies)
echo "  Looking for forwarding rules with prefix: $NAME_PREFIX..."
for rule in $(gcloud compute forwarding-rules list --global --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting forwarding rule $rule..."
    gcloud compute forwarding-rules delete "$rule" --global --quiet
done

# 2. Delete target HTTP proxies (depends on URL maps)
echo "  Looking for HTTP proxies with prefix: $NAME_PREFIX..."
for proxy in $(gcloud compute target-http-proxies list --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting HTTP proxy $proxy..."
    gcloud compute target-http-proxies delete "$proxy" --quiet
done

# 3. Delete URL maps (depends on backend services)
echo "  Looking for URL maps with prefix: $NAME_PREFIX..."
for urlmap in $(gcloud compute url-maps list --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting URL map $urlmap..."
    gcloud compute url-maps delete "$urlmap" --quiet
done

# 4. Delete backend services (depends on NEGs/instance groups)
echo "  Looking for backend services with prefix: $NAME_PREFIX..."
for bs in $(gcloud compute backend-services list --global --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting backend service $bs..."
    gcloud compute backend-services delete "$bs" --global --quiet
done

# 5. Delete NEGs (now safe to delete)
echo "  Looking for network endpoint groups with prefix: $NAME_PREFIX..."
for neg in $(gcloud compute network-endpoint-groups list --global --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting network endpoint group $neg..."
    gcloud compute network-endpoint-groups delete "$neg" --global --quiet
done

# 6. Delete global addresses
echo "  Looking for global addresses with prefix: $NAME_PREFIX..."
for addr in $(gcloud compute addresses list --global --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting global address $addr..."
    gcloud compute addresses delete "$addr" --global --quiet
done

# Delete compute instances with prefix
echo "  Looking for instances with prefix: $NAME_PREFIX..."
for instance in $(gcloud compute instances list --filter="name~^$NAME_PREFIX" --format="value(name,zone)"); do
    name=$(echo "$instance" | awk '{print $1}')
    zone=$(echo "$instance" | awk '{print $2}')
    if [ -n "$name" ] && [ -n "$zone" ]; then
        echo "  Deleting instance $name in zone $zone..."
        gcloud compute instances delete "$name" --zone="$zone" --quiet
    fi
done

# Delete instance groups with prefix
echo "  Looking for instance groups with prefix: $NAME_PREFIX..."
for ig in $(gcloud compute instance-groups list --filter="name~^$NAME_PREFIX" --format="value(name,zone)"); do
    name=$(echo "$ig" | awk '{print $1}')
    zone=$(echo "$ig" | awk '{print $2}')
    if [ -n "$name" ] && [ -n "$zone" ]; then
        echo "  Deleting instance group $name in zone $zone..."
        gcloud compute instance-groups unmanaged delete "$name" --zone="$zone" --quiet
    fi
done

# Delete regional managed instance groups
echo "  Looking for regional managed instance groups with prefix: $NAME_PREFIX..."
for rmig in $(gcloud compute instance-groups managed list --filter="name~^$NAME_PREFIX" --format="value(name,region)" | grep -v "zone:"); do
    name=$(echo "$rmig" | awk '{print $1}')
    region=$(echo "$rmig" | awk '{print $2}')
    if [ -n "$name" ] && [ -n "$region" ]; then
        echo "  Deleting regional managed instance group $name in region $region..."
        gcloud compute instance-groups managed delete "$name" --region="$region" --quiet
    fi
done

# Delete regional autoscalers (need to check each region separately)
echo "  Looking for regional autoscalers with prefix: $NAME_PREFIX..."
# Get all regions where we might have deployed
for region in us-central1 europe-west1 asia-southeast1 us-east1 australia-southeast1; do
    # Check if autoscalers exist in this region
    autoscalers=$(gcloud compute autoscalers list --regions="$region" --filter="name~^$NAME_PREFIX" --format="value(name)" 2>/dev/null || true)
    if [ -n "$autoscalers" ]; then
        for autoscaler in $autoscalers; do
            echo "  Deleting autoscaler $autoscaler in region $region..."
            gcloud compute autoscalers delete "$autoscaler" --region="$region" --quiet || true
        done
    fi
done

# Delete instance templates
echo "  Looking for instance templates with prefix: $NAME_PREFIX..."
for template in $(gcloud compute instance-templates list --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting instance template $template..."
    gcloud compute instance-templates delete "$template" --quiet
done

# Delete health checks with prefix
echo "  Looking for health checks with prefix: $NAME_PREFIX..."
for hc in $(gcloud compute health-checks list --filter="name~^$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting health check $hc..."
    gcloud compute health-checks delete "$hc" --quiet
done

# Delete firewall rules with prefix
echo "  Looking for firewall rules with prefix: $NAME_PREFIX..."
for fw in $(gcloud compute firewall-rules list --filter="name~$NAME_PREFIX" --format="value(name)"); do
    echo "  Deleting firewall rule $fw..."
    gcloud compute firewall-rules delete "$fw" --quiet
done

echo "✅ Cleanup complete!"