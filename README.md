# Tenant Shard Routing with Envoy

This repo implements tenant-based shard routing using Envoy with two available implementations:

1. **WASM Filter with GCS Proxy**
2. **Lua Filter with Tenant Lookup Service**

Both provide high-performance routing based on hostname extraction and GCS-stored tenant-to-shard mappings. I've included both implementations for comparison.

## Architecture

The solution uses a main external Application Load Balancer (ALB) that routes incoming requests to Envoy instance(s). The Envoy instance applies tenant routing logic based on the hostname of the request to determine the appropriate shard. The tenant-to-shard mappings are stored in a Google Cloud Storage (GCS) bucket.

Each shard has its own Application Load Balancer (ALB) that can handle additional routing, as needed. As an example, the shard ALB in this repo routes requests based on path:
- `/*` → Default service backend
- `/foo/*` → Foo service backend
- `/api/*` → API service backend

The Envoy instance can be configured to use either the WASM filter or the Lua filter for tenant routing.

### Single-Region Architecture
In single-region mode, there is one Envoy instance that handles all traffic:
```
User Request → Main ALB → Single Envoy Instance → Shard ALB → Backend Services
```

### Global Multi-Region Architecture
In global mode, Envoy instances are deployed across multiple regions with automatic geo-routing:
```
User Request → Global ALB (Anycast IP) → Nearest Envoy Cluster → Shard ALB → Backend
                    ↓                           ↓
            (Routes to nearest)         (Auto-scales 2-10 instances)
                    ↓                           ↓
    Regions: US Central, Europe,      Each region has independent
    Asia, US East, Australia          scaling and health checks
```

### WASM Filter with GCS Proxy
```
User Request → Main ALB → Envoy (WASM) → Shard ALB → Backend Services
                              ↓
                       Local GCS Proxy
            (Rust service listening on localhost)
                              ↓
                             GCS
                      (tenant mappings)
```

### Lua Filter with Tenant Lookup Service
```
User Request → Main ALB → Envoy (Lua) → Shard ALB → Backend Services
                              ↓
                    Tenant Lookup Service
             (Rust service listening on localhost)
                              ↓
                             GCS
                      (tenant mappings)
```

## Deployment Options

This solution supports two deployment modes:

### 1. Single-Region Deployment (Default)
- One Envoy instance in a single region
- Lower cost, suitable for regional applications
- Simple to manage and debug

### 2. Global Multi-Region Deployment
- Envoy instances deployed across multiple regions worldwide
- Users automatically routed to the nearest Envoy cluster
- High availability with regional failover
- Auto-scaling in each region based on load

## Deployment

Create a `terraform.tfvars` file in the `terraform/` directory with your configuration, based on the provided example:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Run the deployment script:

```bash
./scripts/deploy.sh
```

The script will ask you to choose between:
- **Single Instance**: Deploy Envoy in one region (default)
- **Global**: Deploy Envoy across multiple regions (US, Europe, Asia, etc.)

This will:
- Create a GCS bucket for tenant mappings
- Deploy the main Application Load Balancer (ALB)
- Deploy the Envoy instance(s) with either WASM or Lua filter
- Create shard ALBs with backend services
- Set up health checks and routing rules
- (Global only) Configure Cloud CDN and Cloud Armor for DDoS protection

Create the tenant mappings in the GCS bucket:

```bash
./scripts/setup-test-mappings.sh
```

Test the deployment:

```bash
./scripts/test-deployment.sh
```

## Components

### 1. WASM Filter Implementation (`wasm-filter/`)
- Rust-based Envoy WASM filter using proxy-wasm SDK.
- Uses shared `tenant-routing-core` crate for common logic.
- Extracts tenant from hostname (e.g., `beamreach.example.com` → `beamreach`.)
- Fetches shard mapping from GCS via local proxy (for authentication)
   + If the shard objects were publicly accessible, the proxy service would not be needed.
- Caches tenant mappings for 5 minutes to reduce GCS calls.
- Sets `x-tenant-shard` header for routing to appropriate shard ALB.
- **Limitation**: WASM sandbox prevents direct GCS access with authentication, requiring the separate proxy.

### 2. Lua Filter Implementation
#### Tenant Lookup Service (`tenant-lookup-service/`)
- Rust HTTP service that looks up tenant-to-shard mappings.
- Uses shared `tenant-routing-core` crate for common logic.
- Runs as a Docker container alongside Envoy.
- Fetches mappings from GCS with automatic caching (5 minutes default.)
- Provides simple HTTP API: `GET /lookup?host=beamreach.example.com`.
- Container image stored in Google Container Registry (GCR.)

#### Envoy Lua Filter
- Lua HTTP filter that intercepts requests.
- Extracts tenant from hostname.
- Calls local tenant lookup service for shard mapping.
- Sets routing headers: `x-tenant-shard` and `x-tenant-name`.
- Minimal overhead with local HTTP calls.

### 3. Shared Core Library (`tenant-routing-core/`)
- **Shared Rust crate** used by both WASM filter and tenant lookup service.
- **Common functionality**:
  - Tenant extraction from hostnames.
  - GCS path generation for tenant mappings.
  - Cache entry structures and validation.
  - Configuration management.
  - Shard name normalization.
- **No-std compatible**: Works in both WASM and standard environments.
- **Comprehensive test suite**: Ensures consistency across implementations.

### 4. Terraform Infrastructure (`terraform/`)
- **GCS Bucket**: Stores tenant-to-shard mappings.
- **Main ALB**: Global HTTP load balancer that routes to Envoy.
- **Envoy Instance**: Runs either WASM or Lua filter based on configuration.
- **Shard ALBs**: Each shard has its own ALB for path-based routing.
- **Backend Instances**: Dynamically created based on shard configuration.
- **Modular Design**: Easy to add more shards (shard3, shard4, etc.)

### 5. Test Scripts (`scripts/`)
- `test-deployment.sh`: Basic routing tests.
- `test-full-architecture.sh`: Complete architecture validation including shard ALBs.
- `deploy.sh`: One-command deployment.
- `cleanup.sh`: Clean removal of all resources.
- `build-tenant-lookup.sh`: Build and push tenant lookup service to GCR (Lua implementation only.)

## Setup

### Prerequisites
- Google Cloud Project with billing enabled.
- Terraform installed.
- `gcloud` CLI configured.
- Docker installed (for Lua implementation).

### Tenant Mappings

Tenant-to-shard mappings are stored in GCS bucket as `<tenant>/shard` files.

To add a tenant mapping:
```bash
echo "shard1" | gsutil cp - gs://<bucket>/<tenant-name>/shard
```

Example:
```bash
# After terraform apply, get the bucket name
BUCKET=$(terraform output -raw gcs_bucket)

# Add tenant mappings
echo "shard1" | gsutil cp - gs://$BUCKET/beamreach/shard
echo "shard2" | gsutil cp - gs://$BUCKET/sfco/shard
```

### Configuration by Implementation

#### WASM Filter Configuration
```json
{
  "gcs_bucket": "project-tenant-shard-mapping",
  "cache_ttl_seconds": 300,
  "default_shard": "shard1",
  "proxy_url": "http://localhost:8080"
}
```

#### Lua/Rust Service Configuration
Environment variables (set in startup script):
```bash
GCS_BUCKET=project-tenant-shard-mapping
DEFAULT_SHARD=shard1
CACHE_TTL=300  # Cache duration in seconds
PORT=8080
RUST_LOG=info
```

### Routing Logic

Both implementations follow the same routing logic:

1. **Main ALB** receives request and forwards to Envoy.
2. **Tenant Resolution**:
   - Extract tenant from hostname (e.g., `beamreach.example.com` → `beamreach`.)
   - Fetch mapping from GCS (WASM via proxy, Lua via local service.)
   - Cache mapping for 5 minutes.
   - Set routing headers: `x-tenant-shard` and `x-tenant-name`.
3. **Envoy** routes to the appropriate shard's ALB based on header.
4. **Shard ALB** handles path-based routing:
   - `/foo/*` → foo service backend.
   - `/api/*` → api service backend.
   - `/*` → default service backend.

## Testing

1. First, set up some test tenant mappings:
```bash
./scripts/setup-test-mappings.sh
```

2. Run the test scripts:
```bash
./scripts/test-deployment.sh         # Basic routing tests
./scripts/test-full-architecture.sh  # Full architecture validation
```

These test:
- Tenant-to-shard routing
- Path-based routing within shard ALBs
- Complete flow through all components
- Fallback behavior for unknown tenants

Both implementations pass the same test suite.

## Adding More Shards

To add more shards, update `terraform/terraform.tfvars`:

```hcl
shard_names = ["shard1", "shard2", "shard3", "shard4"]
```

Then apply:
```bash
terraform apply
```

Each shard automatically includes the same services:
- `/` → default service
- `/foo` → foo service (with path rewrite)
- `/api` → api service

## Monitoring

Check Envoy stats:
```bash
curl http://<envoy-ip>:9901/stats?filter=http.ingress_http
```

For Lua implementation, check tenant lookup service:
```bash
curl http://<envoy-ip>:8080/health
```

View logs:
```bash
# Envoy logs
gcloud compute ssh <envoy-instance> --command="sudo docker logs envoy"

# For Lua implementation - tenant lookup service logs
gcloud compute ssh <envoy-instance> --command="sudo docker logs tenant-lookup"

# For WASM implementation - proxy logs
gcloud compute ssh <envoy-instance> --command="sudo journalctl -u gcs-proxy"
```
