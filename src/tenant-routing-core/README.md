# Tenant Routing Core

A shared Rust library that provides common functionality for tenant-based shard routing. This crate is used by both the WASM filter and the tenant lookup service to ensure consistent behavior across implementations.

## Overview

This library provides core functionality for:
- Extracting tenant names from hostnames
- Building GCS paths for tenant mappings
- Managing cache entries with TTL
- Configuration structures
- Shard name normalization

The library is designed to work in both standard and no-std environments, making it suitable for use in WASM filters and regular services.

## Features

### Tenant Extraction
```rust
use tenant_routing_core::tenant::extract_tenant_from_host;

// Extract tenant from hostname
assert_eq!(extract_tenant_from_host("acme-corp.example.com"), Some("acme-corp".to_string()));
assert_eq!(extract_tenant_from_host("tenant.example.com:8080"), Some("tenant".to_string()));
assert_eq!(extract_tenant_from_host("localhost"), None);
assert_eq!(extract_tenant_from_host("192.168.1.1"), None);
```

### GCS Path Generation
```rust
use tenant_routing_core::tenant::{build_gcs_path, build_gcs_object_name};

// Build full GCS path (for URLs)
assert_eq!(build_gcs_path("my-bucket", "tenant1"), "/my-bucket/tenant1/shard");

// Build object name (for GCS API)
assert_eq!(build_gcs_object_name("tenant1"), "tenant1/shard");
```

### Cache Management
```rust
use tenant_routing_core::cache::{CacheEntry, generate_cache_key};

// Create cache entry with TTL
let entry = CacheEntry::with_ttl("shard1".to_string(), current_time, 300);

// Check if entry is still valid
assert!(entry.is_valid(current_time + 299));
assert!(!entry.is_valid(current_time + 301));

// Generate cache keys
assert_eq!(generate_cache_key("tenant1"), "tenant:tenant1");
```

### Configuration
```rust
use tenant_routing_core::config::TenantRoutingConfig;

// Create configuration
let config = TenantRoutingConfig::new(
    "my-bucket".to_string(),
    300,  // 5 minute TTL
    "shard1".to_string()
);

// Validate configuration
assert!(config.validate().is_ok());
```

## No-std Support

The library supports no-std environments for WASM compilation:

```toml
[dependencies]
tenant-routing-core = { version = "0.1", default-features = false, features = ["wasm"] }
```

## Architecture

### Module Structure

- **`config`**: Configuration structures and validation
- **`tenant`**: Tenant extraction and path building functions
- **`cache`**: Cache entry structures and utilities

### Design Principles

1. **Zero Dependencies**: Minimal dependencies for both std and no-std
2. **Type Safety**: Strong typing for all configurations
3. **Validation**: Built-in validation for configurations
4. **Testability**: Comprehensive test suite
5. **Consistency**: Ensures both WASM and service implementations behave identically

## Testing

Run the test suite:
```bash
cargo test
```

Run tests with all features:
```bash
cargo test --all-features
```

## Usage in WASM Filter

```rust
use tenant_routing_core::{
    cache::{CacheEntry, generate_cache_key},
    config::TenantRoutingConfig,
    tenant::{extract_tenant_from_host, build_gcs_path},
};

// Extract tenant from request
let tenant = extract_tenant_from_host(&authority)
    .unwrap_or_else(|| "default".to_string());

// Build GCS path
let path = build_gcs_path(&config.gcs_bucket, &tenant);

// Cache the result
let cache_entry = CacheEntry::with_ttl(shard, current_time, config.cache_ttl_seconds);
```

## Usage in Service

```rust
use tenant_routing_core::{
    config::TenantRoutingConfig,
    tenant::{extract_tenant_from_host, normalize_shard_name},
};

// Extract tenant from hostname
let tenant = extract_tenant_from_host(&host);

// Normalize shard name from GCS
let shard = normalize_shard_name(&raw_shard);
```

## Performance

- **Zero-cost abstractions**: No runtime overhead
- **Small binary size**: Minimal impact on WASM size
- **Fast operations**: All functions are O(1) or O(n) on small strings

## Future Enhancements

Potential additions:
- Advanced tenant validation rules
- Multiple shard mapping strategies
- Prometheus metrics helpers
- More cache backends