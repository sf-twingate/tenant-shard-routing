# Tenant Lookup Service

A lightweight Rust HTTP service that provides tenant-to-shard mapping lookups for Envoy's Lua filter implementation. This service runs alongside Envoy and fetches tenant mappings from Google Cloud Storage (GCS) with built-in caching.

## Overview

The service provides a simple HTTP API that:
- Accepts hostname queries
- Extracts tenant names from hostnames (using shared `tenant-routing-core` logic)
- Fetches shard mappings from GCS
- Caches results for improved performance
- Returns JSON responses for easy parsing in Lua

This service uses the shared `tenant-routing-core` crate to ensure consistent behavior with the WASM filter implementation.

## API

### Health Check
```
GET /health
```
Returns: `OK`

### Tenant Lookup
```
GET /lookup?host=<hostname>
```

Example:
```bash
curl "http://localhost:8080/lookup?host=acme-corp.example.com"
```

Response:
```json
{
  "shard": "shard1",
  "tenant": "acme-corp"
}
```

For unknown tenants, returns the default shard:
```json
{
  "shard": "shard1",
  "tenant": null
}
```

## Configuration

The service is configured via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `GCS_BUCKET` | GCS bucket containing tenant mappings | `tenant-routing-data` |
| `DEFAULT_SHARD` | Default shard for unknown tenants | `shard1` |
| `CACHE_TTL` | Cache duration in seconds | `300` (5 minutes) |
| `PORT` | HTTP server port | `8080` |
| `RUST_LOG` | Log level (trace, debug, info, warn, error) | `info` |

## Building

### Local Development
```bash
cargo build --release
```

### Docker Build
```bash
docker build -t tenant-lookup .
```

### Production Build (for GCR)
```bash
# The build script handles everything
../scripts/build-tenant-lookup.sh
```

## Deployment

The service is deployed as a Docker container alongside Envoy. The Terraform configuration automatically:
1. Pulls the container from GCR
2. Runs it with appropriate environment variables
3. Ensures it's available on localhost:8080 for Envoy

## Architecture

### GCS Structure
Tenant mappings are stored in GCS as:
```
bucket/
  tenant1/
    shard     # Contains: "shard1"
  tenant2/
    shard     # Contains: "shard2"
```

### Caching
- Uses Moka, a high-performance Rust caching library
- TTL-based eviction (default 5 minutes)
- Max capacity: 10,000 entries
- Thread-safe and async-friendly

### Performance
- Startup time: ~100ms
- Memory usage: ~50MB
- Request latency: <1ms (cached), 50-100ms (GCS fetch)
- Concurrent request handling via Tokio

## Docker Image

The Docker image uses a multi-stage build:
1. **Build stage**: Uses rust:nightly-alpine for static compilation
2. **Runtime stage**: Minimal Alpine image with only the binary

Features:
- Static binary (no dynamic dependencies)
- Non-root user (uid 1000)
- Minimal attack surface
- ~15MB final image size

## Dependencies

Key dependencies:
- `axum`: Fast async web framework
- `tokio`: Async runtime
- `google-cloud-storage`: Official GCS client
- `moka`: High-performance cache
- `tracing`: Structured logging
- `tenant-routing-core`: Shared logic for tenant extraction and configuration

## Monitoring

### Logs
The service uses structured logging with tracing:
```
2025-07-21T05:49:36.770060Z  INFO tenant_lookup: Initializing tenant lookup service
2025-07-21T05:49:36.882747Z  INFO tenant_lookup: Server listening on 0.0.0.0:8080
2025-07-21T05:49:40.123456Z  INFO tenant_lookup: Cache hit for tenant: acme-corp -> shard1
```

### Health Monitoring
- Health endpoint at `/health`
- Returns 200 OK when service is ready
- Can be used for container health checks

## Security

- Runs as non-root user
- No external network access required (only GCS)
- Minimal dependencies
- Regular updates via container rebuilds
- GCS access via service account with minimal permissions

## Testing

Run tests:
```bash
cargo test
```

Integration test with real GCS:
```bash
GCS_BUCKET=your-bucket cargo run
# In another terminal:
curl "http://localhost:8080/lookup?host=test.example.com"
```

## Troubleshooting

### Common Issues

1. **GCS Access Denied**
   - Check service account permissions
   - Ensure bucket exists and contains mappings

2. **High Memory Usage**
   - Reduce cache capacity in code
   - Decrease CACHE_TTL

3. **Slow Startup**
   - Check GCS connectivity
   - Verify service account authentication

### Debug Mode
```bash
RUST_LOG=debug cargo run
```

This will show detailed logs including GCS requests and cache operations.