use alloc::string::String;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TenantRoutingConfig {
    pub gcs_bucket: String,
    pub cache_ttl_seconds: u64,
    pub default_shard: String,
}

impl Default for TenantRoutingConfig {
    fn default() -> Self {
        Self {
            gcs_bucket: String::from("tenant-shard-mapping"),
            cache_ttl_seconds: 300,
            default_shard: String::from("shard1"),
        }
    }
}

impl TenantRoutingConfig {
    pub fn new(gcs_bucket: String, cache_ttl_seconds: u64, default_shard: String) -> Self {
        Self {
            gcs_bucket,
            cache_ttl_seconds,
            default_shard,
        }
    }

    pub fn validate(&self) -> Result<(), &'static str> {
        if self.gcs_bucket.is_empty() {
            return Err("GCS bucket name cannot be empty");
        }
        if self.default_shard.is_empty() {
            return Err("Default shard cannot be empty");
        }
        if self.cache_ttl_seconds == 0 {
            return Err("Cache TTL must be greater than 0");
        }
        Ok(())
    }
}
