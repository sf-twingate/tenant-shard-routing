# Terraform Modules

This directory contains reusable Terraform modules for the tenant routing infrastructure.

## Module Structure

### health-checks
Creates health check resources and firewall rules for Google Cloud Load Balancers.

**Outputs:**
- `health_check_id` - ID of the health check resource
- `backend_tags` - Firewall tags for backend instances
- `envoy_tags` - Firewall tags for Envoy instances

### gcs
Manages GCS bucket for tenant-shard mappings with proper service account permissions.

**Inputs:**
- `project_id` - GCP project ID
- `region` - GCS bucket region
- `name_prefix` - Resource naming prefix
- `shard_names` - List of shard names for initial mappings

**Outputs:**
- `bucket_name` - GCS bucket name
- `service_account_email` - Service account for Envoy access

**Features:**
- Creates service account with GCS read permissions
- Optionally grants GCR pull permissions for containerized deployments
- Manages bucket lifecycle policies

### envoy
Deploys Envoy proxy with either WASM filter or Lua filter for tenant-based routing.

**Inputs:**
- `name_prefix` - Resource naming prefix
- `zone` - GCP zone for deployment
- `shard_names` - List of shard names
- `shard_backends` - Map of shard backend services
- `gcs_bucket_name` - GCS bucket for tenant mappings
- `service_account_email` - Service account for GCS access
- `wasm_filter_path` - Path to WASM filter source
- `use_lua_filter` - Boolean to toggle between WASM and Lua implementations
- `project_id` - GCP project ID (required for Lua implementation)

**Outputs:**
- `instance_id` - Envoy instance ID
- `instance_group_id` - Envoy instance group ID
- `external_ip` - External IP address

**Features:**
- Supports two implementations:
  - **WASM Filter**: Builds filter on instance, uses local proxy for GCS
  - **Lua Filter**: Uses containerized Rust service from GCR
- Automatic startup script selection based on implementation
- Configures routing rules for tenant-based sharding

### main-load-balancer
Creates the main Application Load Balancer that routes traffic to Envoy.

**Inputs:**
- `name_prefix` - Resource naming prefix
- `domain` - Domain for SSL certificate
- `envoy_instance_group_id` - Envoy instance group to route to
- `health_check_id` - Health check for backends

**Outputs:**
- `load_balancer_ip` - External IP address
- `ssl_certificate_status` - SSL provisioning status

### shard
Creates a shard with its own ALB and backend services. Uses `route_rules` for advanced path-based routing.

**Inputs:**
- `shard_name` - Name of the shard
- `region` - GCP region
- `zone` - GCP zone
- `health_check_id` - Health check for backends

**Outputs:**
- `shard_alb_backend_service_id` - Backend service ID for routing
- `shard_alb_ip` - External IP of shard ALB
- `service_instances` - Map of service instance IPs

**Features:**
- Creates three services per shard:
  - Default service (handles `/` paths)
  - Foo service (handles `/foo` paths with path rewrite)
  - API service (handles `/api` paths)
- Each service has its own backend instance group
- Automatic path-based routing configuration

## Implementation Toggle

The infrastructure supports two implementations that can be toggled via the `use_lua_filter` variable:

### WASM Implementation (default)
```hcl
module "envoy" {
  source = "./modules/envoy"
  use_lua_filter = false  # or omit for default
  # ... other variables
}
```

### Lua Implementation (recommended)
```hcl
module "envoy" {
  source = "./modules/envoy"
  use_lua_filter = true
  project_id = var.project_id  # Required for GCR access
  # ... other variables
}
```

## Module Benefits

1. **Modularity** - Each component is self-contained and reusable
2. **Maintainability** - Easier to update and test individual components
3. **Scalability** - Simple to add new shards or modify existing ones
4. **Flexibility** - Support for multiple implementation patterns
5. **Best Practices** - Follows Terraform module best practices with clear interfaces

## Directory Structure

```
modules/
├── envoy/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── templates/
│       ├── envoy-wasm.yaml.tpl      # WASM configuration
│       ├── envoy-wasm-startup.sh.tpl # WASM startup script
│       ├── envoy-lua.yaml.tpl       # Lua configuration
│       └── envoy-lua-startup.sh.tpl  # Lua startup script
├── gcs/
├── health-checks/
├── main-load-balancer/
└── shard/
```