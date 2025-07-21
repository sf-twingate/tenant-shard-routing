use alloc::format;
use alloc::string::{String, ToString};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct CacheEntry {
    pub shard: String,
    pub expiry: u64,
}

impl CacheEntry {
    pub fn new(shard: String, expiry: u64) -> Self {
        Self { shard, expiry }
    }

    pub fn is_valid(&self, current_time: u64) -> bool {
        self.expiry > current_time
    }

    pub fn with_ttl(shard: String, current_time: u64, ttl_seconds: u64) -> Self {
        Self {
            shard,
            expiry: current_time + ttl_seconds,
        }
    }
}

pub fn generate_cache_key(tenant: &str) -> String {
    format!("tenant:{}", tenant)
}

pub fn parse_cache_key(key: &str) -> Option<String> {
    key.strip_prefix("tenant:").map(|s| s.to_string())
}
