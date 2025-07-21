#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Try to get IPs from Terraform outputs if not provided as arguments
if [ -z "$1" ]; then
    # Try to get Envoy IP from Terraform
    ENVOY_IP=$(cd "$SCRIPT_DIR/../terraform" && terraform output -raw envoy_ip 2>/dev/null || echo "")
    if [ -z "$ENVOY_IP" ]; then
        echo "Error: Could not get Envoy IP from Terraform outputs and no IP provided as argument"
        echo "Usage: $0 [ENVOY_IP] [LB_IP]"
        exit 1
    fi
else
    ENVOY_IP=$1
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
echo "Envoy IP: $ENVOY_IP"
echo "Load Balancer IP: ${LB_IP:-Not available}"
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

# Wait for Envoy to be ready
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

# Test Envoy directly
echo -e "${YELLOW}Testing Envoy directly (http://$ENVOY_IP)${NC}"
test_route "beamreach default path" "http://$ENVOY_IP/" "beamreach.example.com" "1" "default"
test_route "beamreach /foo path" "http://$ENVOY_IP/foo" "beamreach.example.com" "1" "foo"
test_route "beamreach /api path" "http://$ENVOY_IP/api" "beamreach.example.com" "1" "api"
test_route "sfco default path" "http://$ENVOY_IP/" "sfco.example.com" "2" "default"
test_route "sfco /foo path" "http://$ENVOY_IP/foo" "sfco.example.com" "2" "foo"
test_route "sfco /api path" "http://$ENVOY_IP/api" "sfco.example.com" "2" "api"
test_route "corp default path" "http://$ENVOY_IP/" "corp.example.com" "1" "default"
test_route "corp /api path" "http://$ENVOY_IP/api" "corp.example.com" "1" "api"
test_route "foo /foo path" "http://$ENVOY_IP/foo" "foo.example.com" "2" "foo"
test_route "foo /api path" "http://$ENVOY_IP/api" "foo.example.com" "2" "api"
test_route "unknown tenant (should use /default/shard)" "http://$ENVOY_IP/" "unknown.example.com" "1" "default"

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
    test_route "corp /api path via LB" "http://$LB_IP/api" "corp.example.com" "1" "api"
    test_route "foo /foo path via LB" "http://$LB_IP/foo" "foo.example.com" "2" "foo"
    test_route "foo /api path via LB" "http://$LB_IP/api" "foo.example.com" "2" "api"
    test_route "unknown tenant via LB (should use /default/shard)" "http://$LB_IP/" "unknown.example.com" "1" "default"
fi

# Check Envoy admin stats (with timeout to prevent hanging)
echo ""
echo -e "${YELLOW}Envoy Admin Stats:${NC}"
timeout 5 curl -s "http://$ENVOY_IP:9901/stats?filter=http.ingress_http" 2>/dev/null | grep -E "(downstream_rq_total|upstream_rq_total)" | head -10 || echo "Stats request timed out or no matching stats found"

echo ""
echo -e "${GREEN}Testing complete!${NC}"