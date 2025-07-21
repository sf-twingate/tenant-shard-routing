#!/bin/bash

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get Terraform outputs
cd "$SCRIPT_DIR/../terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Full Architecture Test ===${NC}"
echo ""
echo "Note: This test assumes you have set up tenant mappings."
echo "Run ./setup-test-mappings.sh if you haven't already."
echo ""

# Get IPs from Terraform
ENVOY_IP=$(terraform output -raw envoy_ip 2>/dev/null || echo "")
LB_IP=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")

# Check if this is a global deployment
IS_GLOBAL=false
if [ -z "$ENVOY_IP" ] && terraform output -json envoy_global_info 2>/dev/null | grep -q "regions_deployed"; then
    IS_GLOBAL=true
    ENVOY_IP="GLOBAL"
    echo -e "${BLUE}Detected global deployment${NC}"
fi

# Get shard information
echo -e "${YELLOW}Getting shard ALB information...${NC}"
SHARDS_JSON=$(terraform output -json shards 2>/dev/null || echo "{}")

# Function to test routing
test_route() {
    local test_name=$1
    local url=$2
    local host_header=$3
    local expected_shard=$4
    local expected_service=$5
    
    echo -n "Testing $test_name... "
    
    # Test with host header if provided
    if [ -n "$host_header" ]; then
        response=$(curl -s -H "Host: $host_header" "$url" 2>/dev/null || echo "{}")
    else
        response=$(curl -s "$url" 2>/dev/null || echo "{}")
    fi
    
    # Check for HTML response with shard and service info
    if echo "$response" | grep -q "<title>shard$expected_shard - $expected_service</title>"; then
        echo -e "${GREEN}✓ Routed to shard$expected_shard-$expected_service${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed - Expected shard$expected_shard-$expected_service${NC}"
        echo "Response: $(echo "$response" | head -1)"
        return 1
    fi
}

# Test shard ALBs directly
echo -e "${YELLOW}1. Testing Shard ALBs Directly${NC}"
echo "   (Verifying path-based routing within each shard)"
echo ""

# Extract shard ALB IPs using jq
if command -v jq &> /dev/null; then
    for shard in shard1 shard2; do
        ALB_IP=$(echo "$SHARDS_JSON" | jq -r ".${shard}.alb_ip // empty")
        if [ -n "$ALB_IP" ]; then
            echo -e "${BLUE}Testing ${shard} ALB (http://$ALB_IP)${NC}"
            test_route "${shard} default path" "http://$ALB_IP/" "" "${shard#shard}" "default"
            test_route "${shard} /foo path" "http://$ALB_IP/foo" "" "${shard#shard}" "foo"
            test_route "${shard} /api path" "http://$ALB_IP/api" "" "${shard#shard}" "api"
            echo ""
        fi
    done
else
    echo "jq not installed, skipping direct shard ALB tests"
    echo ""
fi

# Test Envoy routing to shard ALBs (skip for global deployment)
if [ "$IS_GLOBAL" != "true" ]; then
    echo -e "${YELLOW}2. Testing Envoy Router (http://$ENVOY_IP)${NC}"
    echo "   (Verifying tenant-based routing to correct shard ALB)"
    echo ""

    test_route "beamreach → shard1 default" "http://$ENVOY_IP/" "beamreach.example.com" "1" "default"
    test_route "beamreach → shard1 /foo" "http://$ENVOY_IP/foo" "beamreach.example.com" "1" "foo"
    test_route "beamreach → shard1 /api" "http://$ENVOY_IP/api" "beamreach.example.com" "1" "api"
    test_route "sfco → shard2 default" "http://$ENVOY_IP/" "sfco.example.com" "2" "default"
    test_route "sfco → shard2 /foo" "http://$ENVOY_IP/foo" "sfco.example.com" "2" "foo"
    test_route "sfco → shard2 /api" "http://$ENVOY_IP/api" "sfco.example.com" "2" "api"
    test_route "corp → shard1 default" "http://$ENVOY_IP/" "corp.example.com" "1" "default"
    test_route "corp → shard1 /api" "http://$ENVOY_IP/api" "corp.example.com" "1" "api"
    test_route "foo → shard2 /foo" "http://$ENVOY_IP/foo" "foo.example.com" "2" "foo"
    test_route "foo → shard2 /api" "http://$ENVOY_IP/api" "foo.example.com" "2" "api"
    test_route "unknown → default shard" "http://$ENVOY_IP/" "unknown.example.com" "1" "default"
else
    echo -e "${YELLOW}2. Skipping direct Envoy tests (global deployment)${NC}"
    echo "   In global deployments, Envoy instances are accessed through the load balancer"
fi

# Test through main Load Balancer
if [ -n "$LB_IP" ]; then
    echo ""
    echo -e "${YELLOW}3. Testing Main Load Balancer (http://$LB_IP)${NC}"
    echo "   (Complete flow: LB → Envoy → Shard ALB → Backend)"
    echo ""
    
    test_route "beamreach full flow default" "http://$LB_IP/" "beamreach.example.com" "1" "default"
    test_route "beamreach full flow /foo" "http://$LB_IP/foo" "beamreach.example.com" "1" "foo"
    test_route "beamreach full flow /api" "http://$LB_IP/api" "beamreach.example.com" "1" "api"
    test_route "sfco full flow default" "http://$LB_IP/" "sfco.example.com" "2" "default"
    test_route "sfco full flow /foo" "http://$LB_IP/foo" "sfco.example.com" "2" "foo"
    test_route "sfco full flow /api" "http://$LB_IP/api" "sfco.example.com" "2" "api"
    test_route "corp full flow default" "http://$LB_IP/" "corp.example.com" "1" "default"
    test_route "corp full flow /api" "http://$LB_IP/api" "corp.example.com" "1" "api"
    test_route "foo full flow /foo" "http://$LB_IP/foo" "foo.example.com" "2" "foo"
    test_route "foo full flow /api" "http://$LB_IP/api" "foo.example.com" "2" "api"
fi

# Architecture diagram
echo ""
echo -e "${BLUE}Architecture Flow:${NC}"
echo "┌─────────────┐    ┌───────────┐    ┌────────────┐    ┌─────────┐"
echo "│   Client    │───▶│ Main ALB  │───▶│   Envoy    │───▶│ Shard   │"
echo "│ (beamreach) │    │           │    │  (WASM)    │    │  ALB    │"
echo "└─────────────┘    └───────────┘    └────────────┘    └─────────┘"
echo "                                            │                 │"
echo "                                            ▼                 ▼"
echo "                                          GCS         ┌────────────┐"
echo "                                     (mappings)       │  Backend   │"
echo "                                                      │ Services   │"
echo "                                                      └────────────┘"

echo ""
echo -e "${GREEN}Testing complete!${NC}"