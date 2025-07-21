#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Try to get IPs from Terraform outputs if not provided as arguments
if [ -z "$1" ]; then
    # Try to get Envoy IP from Terraform
    ENVOY_IP=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw envoy_ip 2>/dev/null || echo "")
    if [ -z "$ENVOY_IP" ]; then
        # Check if this is a global deployment
        if cd "$SCRIPT_DIR/../terraform" && terraform output -json envoy_global_info 2>/dev/null | grep -q "regions_deployed"; then
            ENVOY_IP="GLOBAL"
            echo "Detected global deployment - will test through load balancer only"
        else
            echo "Error: Could not get Envoy IP from Terraform outputs and no IP provided as argument"
            echo "Usage: $0 [ENVOY_IP] [LB_IP]"
            exit 1
        fi
    fi
else
    ENVOY_IP=$1
    # Handle empty string as global deployment
    if [ -z "$ENVOY_IP" ]; then
        ENVOY_IP="GLOBAL"
    fi
fi

if [ -z "$2" ]; then
    # Try to get Load Balancer IP from Terraform
    LB_IP=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw load_balancer_ip 2>/dev/null || echo "")
else
    LB_IP=$2
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Testing Shard Routing ===${NC}"
if [ "$ENVOY_IP" = "GLOBAL" ]; then
    echo "Deployment Type: Global (multi-region)"
    echo "Testing will be performed through the load balancer only"
else
    echo "Deployment Type: Single-region"
    echo "Envoy IP: $ENVOY_IP"
fi
echo "Load Balancer IP: ${LB_IP:-Not available}"
echo ""

# Show current tenant mappings
"$SCRIPT_DIR/show-tenant-mappings-compact.sh"
echo ""
echo "Note: This test assumes you have set up tenant mappings."
echo "Run ./setup-test-mappings.sh if you haven't already."
echo ""

# Function to test routing
test_route() {
    local test_name=$1
    local url=$2
    local host_header=$3
    local expected_shard=$4
    local expected_service=$5
    
    echo -n "Testing $test_name... "
    
    # Test against Envoy directly
    response=$(curl -s -H "Host: $host_header" "$url" 2>/dev/null || echo "{}")
    
    # Check for HTML response with shard and service info
    if echo "$response" | grep -q "<title>shard$expected_shard - $expected_service</title>"; then
        echo -e "${GREEN}✓ Routed to shard$expected_shard-$expected_service${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed - Expected shard$expected_shard-$expected_service${NC}"
        echo "Response title: $(echo "$response" | grep -o '<title>[^<]*</title>' | head -1)"
        return 1
    fi
}

# Wait for infrastructure to be ready
if [ "$ENVOY_IP" != "GLOBAL" ]; then
    echo -e "${YELLOW}Waiting for Envoy to be ready...${NC}"
    for i in {1..30}; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$ENVOY_IP" 2>&1)
        curl_exit_code=$?
        
        if echo "$http_code" | grep -q "200\|404\|502"; then
            echo "Envoy is responding (HTTP $http_code)"
            break
        fi
        
        if [ $curl_exit_code -ne 0 ]; then
            echo -e "\n${RED}Curl failed with exit code $curl_exit_code${NC}"
            echo "Trying to connect to: http://$ENVOY_IP"
            echo "Error details:"
            curl -v "http://$ENVOY_IP" 2>&1 | head -10
        else
            echo -n "."
            echo " (HTTP: $http_code)"
        fi
        
        sleep 2
    done
    echo ""
else
    echo -e "${YELLOW}Waiting for global infrastructure to be ready...${NC}"
    # For global deployment, check if load balancer is responding
    for i in {1..30}; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: beamreach.example.com" "http://$LB_IP" 2>&1)
        
        if echo "$http_code" | grep -q "200\|404\|502\|503"; then
            echo "Load balancer is responding (HTTP $http_code)"
            break
        fi
        
        echo -n "."
        sleep 2
    done
    echo ""
fi

# Test Envoy directly (only for single-region deployment)
if [ "$ENVOY_IP" != "GLOBAL" ]; then
    echo -e "${YELLOW}Testing Envoy directly (http://$ENVOY_IP)${NC}"
    test_route "beamreach default path" "http://$ENVOY_IP/" "beamreach.example.com" "1" "default"
    test_route "beamreach /foo path" "http://$ENVOY_IP/foo" "beamreach.example.com" "1" "foo"
    test_route "beamreach /api path" "http://$ENVOY_IP/api" "beamreach.example.com" "1" "api"
    test_route "sfco default path" "http://$ENVOY_IP/" "sfco.example.com" "2" "default"
    test_route "sfco /foo path" "http://$ENVOY_IP/foo" "sfco.example.com" "2" "foo"
    test_route "sfco /api path" "http://$ENVOY_IP/api" "sfco.example.com" "2" "api"
    test_route "corp default path" "http://$ENVOY_IP/" "corp.example.com" "1" "default"
    test_route "corp /foo path" "http://$ENVOY_IP/foo" "corp.example.com" "1" "foo"
    test_route "corp /api path" "http://$ENVOY_IP/api" "corp.example.com" "1" "api"
    test_route "foo default path" "http://$ENVOY_IP/" "foo.example.com" "2" "default"
    test_route "foo /foo path" "http://$ENVOY_IP/foo" "foo.example.com" "2" "foo"
    test_route "foo /api path" "http://$ENVOY_IP/api" "foo.example.com" "2" "api"
    test_route "unknown tenant (should use /default/shard)" "http://$ENVOY_IP/" "unknown.example.com" "1" "default"
fi

# Test through Load Balancer (if available)
if [ -n "$LB_IP" ]; then
    echo ""
    echo -e "${YELLOW}Testing through Load Balancer (http://$LB_IP)${NC}"
    
    test_route "beamreach default path via LB" "http://$LB_IP/" "beamreach.example.com" "1" "default"
    test_route "beamreach /foo path via LB" "http://$LB_IP/foo" "beamreach.example.com" "1" "foo"
    test_route "beamreach /api path via LB" "http://$LB_IP/api" "beamreach.example.com" "1" "api"
    test_route "sfco default path via LB" "http://$LB_IP/" "sfco.example.com" "2" "default"
    test_route "sfco /foo path via LB" "http://$LB_IP/foo" "sfco.example.com" "2" "foo"
    test_route "sfco /api path via LB" "http://$LB_IP/api" "sfco.example.com" "2" "api"
    test_route "corp default path via LB" "http://$LB_IP/" "corp.example.com" "1" "default"
    test_route "corp /foo path via LB" "http://$LB_IP/foo" "corp.example.com" "1" "foo"
    test_route "corp /api path via LB" "http://$LB_IP/api" "corp.example.com" "1" "api"
    test_route "foo default path via LB" "http://$LB_IP/" "foo.example.com" "2" "default"
    test_route "foo /foo path via LB" "http://$LB_IP/foo" "foo.example.com" "2" "foo"
    test_route "foo /api path via LB" "http://$LB_IP/api" "foo.example.com" "2" "api"
    test_route "unknown tenant via LB (should use /default/shard)" "http://$LB_IP/" "unknown.example.com" "1" "default"
fi

# Check Envoy admin stats (only for single-region deployment)
if [ "$ENVOY_IP" != "GLOBAL" ]; then
    echo ""
    echo -e "${YELLOW}Envoy Admin Stats:${NC}"
    
    # Get the instance name
    INSTANCE_NAME=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw envoy_instance_name 2>/dev/null || echo "")
    if [ -z "$INSTANCE_NAME" ]; then
        # Try to guess the instance name from the prefix
        PREFIX=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw name_prefix 2>/dev/null || echo "tenant-routing")
        INSTANCE_NAME="${PREFIX}-envoy"
    fi
    
    # Get the zone
    ZONE=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw envoy_zone 2>/dev/null || echo "us-central1-a")
    
    # Try to fetch stats directly via SSH command
    echo "Fetching Envoy admin stats..."
    echo "Instance: $INSTANCE_NAME, Zone: $ZONE"
    
    # Fetch stats via SSH
    echo "Fetching stats via IAP SSH..."
    
    # Run curl command on the remote instance via SSH - get multiple stat categories
    STATS=$(timeout 15 gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --tunnel-through-iap --command="curl -s 'http://localhost:9901/stats' 2>&1" 2>&1 | grep -vE "(WARNING:|Warning: Permanently added|SSH connection successful)")
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        if [ -n "$STATS" ]; then
            echo ""
            echo "Request Statistics:"
            echo "$STATS" | grep -E "http.ingress_http.downstream_rq_total:" | head -1 || echo "  No downstream requests"
            echo "$STATS" | grep -E "http.ingress_http.downstream_rq_2xx:" | head -1 || echo "  No 2xx responses"
            echo "$STATS" | grep -E "http.ingress_http.downstream_rq_3xx:" | head -1 || echo "  No 3xx responses"
            echo "$STATS" | grep -E "http.ingress_http.downstream_rq_4xx:" | head -1 || echo "  No 4xx responses"
            echo "$STATS" | grep -E "http.ingress_http.downstream_rq_5xx:" | head -1 || echo "  No 5xx responses"
            
            echo ""
            echo "Cluster Statistics:"
            echo "$STATS" | grep -E "cluster.shard[0-9]+.upstream_rq_total:" | head -5
            echo "$STATS" | grep -E "cluster.shard[0-9]+.upstream_rq_active:" | head -5
            
            echo ""
            echo "Connection Statistics:"
            echo "$STATS" | grep -E "http.ingress_http.downstream_cx_total:" | head -1
            echo "$STATS" | grep -E "http.ingress_http.downstream_cx_active:" | head -1
            
            # Show any errors
            ERROR_COUNT=$(echo "$STATS" | grep -E "(failed|error|timeout)" | grep -v ": 0$" | wc -l)
            if [ $ERROR_COUNT -gt 0 ]; then
                echo ""
                echo "Errors/Failures:"
                echo "$STATS" | grep -E "(failed|error|timeout)" | grep -v ": 0$" | head -5
            fi
        else
            echo "No stats available"
        fi
    else
        echo "SSH connection failed."
        echo ""
        echo "IAP SSH firewall rule may need to be applied."
        echo "Run 'terraform apply' to enable SSH access via IAP."
    fi
else
    echo ""
    echo -e "${YELLOW}Global Deployment Stats:${NC}"
    
    # Get regions from terraform output
    REGIONS=$(cd "$SCRIPT_DIR/../terraform" && terraform output -json envoy_global_info 2>/dev/null | jq -r '.regions_deployed[]' 2>/dev/null || echo "")
    
    if [ -n "$REGIONS" ]; then
        echo "Collecting stats from all regions..."
        echo ""
        
        # Get name prefix from terraform
        NAME_PREFIX=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw name_prefix 2>/dev/null || echo "tenant-routing")
        
        # For each region, try to get stats from one instance
        for REGION in $REGIONS; do
            echo -e "${YELLOW}Region: $REGION${NC}"
            
            # Find the actual MIG name for this region by listing MIGs and matching the pattern
            MIG_NAME=$(gcloud compute instance-groups managed list --filter="region:$REGION AND name:${NAME_PREFIX}-envoy*" --format="value(name)" 2>/dev/null | grep -E "${NAME_PREFIX}-envoy-.*-rmig$" | head -1)
            
            if [ -z "$MIG_NAME" ]; then
                echo "  No Envoy managed instance group found in this region"
                echo ""
                continue
            fi
            
            # List instances in this region's managed instance group
            INSTANCES=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" --region="$REGION" --format="get(instance)" 2>/dev/null | head -1)
            
            if [ -n "$INSTANCES" ]; then
                # The instance field contains the full URL, extract the instance name
                # Format: https://www.googleapis.com/compute/v1/projects/{project}/zones/{zone}/instances/{instance-name}
                INSTANCE_NAME=$(echo "$INSTANCES" | grep -oE '[^/]+$')
                echo "  Found instance: $INSTANCE_NAME"
                
                # For managed instance groups, the zone is embedded in the instance name
                # Format is usually: {prefix}-{region}-{random}-{zone}
                # Try to extract zone from the instance name
                ZONE=$(echo "$INSTANCE_NAME" | grep -oE '[a-z]+-[a-z]+[0-9]-[a-z]$' | tail -1)
                
                if [ -z "$ZONE" ]; then
                    # Fallback: List all instances and find our instance
                    INSTANCE_INFO=$(gcloud compute instances list --filter="name=$INSTANCE_NAME" --format="value(name,zone)" 2>/dev/null | head -1)
                    if [ -n "$INSTANCE_INFO" ]; then
                        ZONE=$(echo "$INSTANCE_INFO" | awk '{print $2}')
                        ZONE=$(basename "$ZONE")
                    fi
                fi
                
                if [ -n "$ZONE" ]; then
                    echo "  Fetching stats from $INSTANCE_NAME in $ZONE..."
                    
                    # Fetch stats from this instance
                    STATS=$(timeout 10 gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --tunnel-through-iap --command="curl -s 'http://localhost:9901/stats' 2>&1" 2>&1 | grep -vE "(WARNING:|Warning: Permanently added|SSH connection successful)")
                    EXIT_CODE=$?
                    
                    if [ $EXIT_CODE -eq 0 ] && [ -n "$STATS" ]; then
                        # Show condensed stats for each region
                        TOTAL_REQ=$(echo "$STATS" | grep -E "http.ingress_http.downstream_rq_total:" | head -1 | grep -o '[0-9]*$' || echo "0")
                        ACTIVE_CONN=$(echo "$STATS" | grep -E "http.ingress_http.downstream_cx_active:" | head -1 | grep -o '[0-9]*$' || echo "0")
                        SUCCESS_2XX=$(echo "$STATS" | grep -E "http.ingress_http.downstream_rq_2xx:" | head -1 | grep -o '[0-9]*$' || echo "0")
                        ERRORS_5XX=$(echo "$STATS" | grep -E "http.ingress_http.downstream_rq_5xx:" | head -1 | grep -o '[0-9]*$' || echo "0")
                        
                        if [ "$TOTAL_REQ" = "0" ]; then
                            echo "  No traffic received yet in this region"
                        else
                            echo "  Total Requests: $TOTAL_REQ"
                            echo "  Active Connections: $ACTIVE_CONN"
                            echo "  Success (2xx): $SUCCESS_2XX"
                            if [ "$ERRORS_5XX" != "0" ] && [ "$ERRORS_5XX" != "" ]; then
                                echo -e "  ${RED}Errors (5xx): $ERRORS_5XX${NC}"
                            fi
                            
                            # Show shard distribution
                            echo "  Shard Distribution:"
                            SHARD_STATS=$(echo "$STATS" | grep -E "cluster.shard[0-9]+.upstream_rq_total:" | sed 's/^/    /')
                            if [ -n "$SHARD_STATS" ]; then
                                echo "$SHARD_STATS" | head -3
                            else
                                echo "    No shard traffic yet"
                            fi
                        fi
                    else
                        echo "  Unable to fetch stats (exit code: $EXIT_CODE)"
                        if [ -n "$STATS" ]; then
                            echo "  Error: $(echo "$STATS" | head -1)"
                        fi
                    fi
                else
                    echo "  Could not determine zone for instance"
                fi
            else
                echo "  No instances found in managed instance group"
            fi
            echo ""
        done
        
        echo "Note: Stats shown are from one instance per region."
        echo "Use monitoring dashboard for comprehensive multi-region metrics."
    else
        echo "Unable to determine deployed regions from Terraform output"
        echo "Use monitoring dashboard to view per-region stats"
    fi
fi

echo ""
echo -e "${GREEN}Testing complete!${NC}"