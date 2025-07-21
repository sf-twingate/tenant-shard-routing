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
