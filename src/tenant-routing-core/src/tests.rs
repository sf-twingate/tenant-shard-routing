#[cfg(test)]
mod config_tests {
    use crate::config::TenantRoutingConfig;

    #[test]
    fn test_default_config() {
        let config = TenantRoutingConfig::default();
        assert_eq!(config.gcs_bucket, "tenant-shard-mapping");
        assert_eq!(config.cache_ttl_seconds, 300);
        assert_eq!(config.default_shard, "shard1");
    }

    #[test]
    fn test_config_validation() {
        let valid_config = TenantRoutingConfig::new(
            "my-bucket".to_string(),
            300,
            "shard1".to_string(),
        );
        assert!(valid_config.validate().is_ok());

        let invalid_bucket = TenantRoutingConfig::new(
            "".to_string(),
            300,
            "shard1".to_string(),
        );
        assert_eq!(invalid_bucket.validate(), Err("GCS bucket name cannot be empty"));

        let invalid_shard = TenantRoutingConfig::new(
            "my-bucket".to_string(),
            300,
            "".to_string(),
        );
        assert_eq!(invalid_shard.validate(), Err("Default shard cannot be empty"));

        let invalid_ttl = TenantRoutingConfig::new(
            "my-bucket".to_string(),
            0,
            "shard1".to_string(),
        );
        assert_eq!(invalid_ttl.validate(), Err("Cache TTL must be greater than 0"));
    }
}

#[cfg(test)]
mod tenant_tests {
    use crate::tenant::*;

    #[test]
    fn test_extract_tenant_from_host() {
        // Valid cases
        assert_eq!(extract_tenant_from_host("tenant1.example.com"), Some("tenant1".to_string()));
        assert_eq!(extract_tenant_from_host("tenant-2.example.com"), Some("tenant-2".to_string()));
        assert_eq!(extract_tenant_from_host("tenant_3.example.com"), Some("tenant_3".to_string()));
        assert_eq!(extract_tenant_from_host("tenant1.example.com:8080"), Some("tenant1".to_string()));
        assert_eq!(extract_tenant_from_host("sub.domain.example.com"), Some("sub".to_string()));
        
        // Invalid cases
        assert_eq!(extract_tenant_from_host("localhost"), None);
        assert_eq!(extract_tenant_from_host("example"), None);
        assert_eq!(extract_tenant_from_host("192.168.1.1"), None);
        assert_eq!(extract_tenant_from_host("10.0.0.1:8080"), None);
        assert_eq!(extract_tenant_from_host(""), None);
        assert_eq!(extract_tenant_from_host(".example.com"), None);
        assert_eq!(extract_tenant_from_host("tenant@.example.com"), None);
        assert_eq!(extract_tenant_from_host("tenant!.example.com"), None);
    }

    #[test]
    fn test_build_gcs_path() {
        assert_eq!(build_gcs_path("my-bucket", "tenant1"), "/my-bucket/tenant1/shard");
        assert_eq!(build_gcs_path("another-bucket", "tenant-2"), "/another-bucket/tenant-2/shard");
    }

    #[test]
    fn test_build_gcs_object_name() {
        assert_eq!(build_gcs_object_name("tenant1"), "tenant1/shard");
        assert_eq!(build_gcs_object_name("tenant-2"), "tenant-2/shard");
    }

    #[test]
    fn test_normalize_shard_name() {
        assert_eq!(normalize_shard_name("shard1"), "shard1");
        assert_eq!(normalize_shard_name("SHARD1"), "shard1");
        assert_eq!(normalize_shard_name("  shard1  "), "shard1");
        assert_eq!(normalize_shard_name("  SHARD1  \n"), "shard1");
    }
}

#[cfg(test)]
mod cache_tests {
    use crate::cache::*;

    #[test]
    fn test_cache_entry_creation() {
        let entry = CacheEntry::new("shard1".to_string(), 1000);
        assert_eq!(entry.shard, "shard1");
        assert_eq!(entry.expiry, 1000);
    }

    #[test]
    fn test_cache_entry_validation() {
        let entry = CacheEntry::new("shard1".to_string(), 1000);
        
        // Valid when current time is before expiry
        assert!(entry.is_valid(999));
        
        // Invalid when current time is at or after expiry
        assert!(!entry.is_valid(1000));
        assert!(!entry.is_valid(1001));
    }

    #[test]
    fn test_cache_entry_with_ttl() {
        let current_time = 1000;
        let ttl = 300;
        let entry = CacheEntry::with_ttl("shard1".to_string(), current_time, ttl);
        
        assert_eq!(entry.shard, "shard1");
        assert_eq!(entry.expiry, 1300);
        assert!(entry.is_valid(1299));
        assert!(!entry.is_valid(1300));
    }

    #[test]
    fn test_cache_key_generation() {
        assert_eq!(generate_cache_key("tenant1"), "tenant:tenant1");
        assert_eq!(generate_cache_key("tenant-2"), "tenant:tenant-2");
    }

    #[test]
    fn test_cache_key_parsing() {
        assert_eq!(parse_cache_key("tenant:tenant1"), Some("tenant1".to_string()));
        assert_eq!(parse_cache_key("tenant:tenant-2"), Some("tenant-2".to_string()));
        assert_eq!(parse_cache_key("invalid"), None);
        assert_eq!(parse_cache_key(""), None);
    }

    #[test]
    fn test_cache_entry_serialization() {
        let entry = CacheEntry::new("shard1".to_string(), 1000);
        
        // Test JSON serialization
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"shard\":\"shard1\""));
        assert!(json.contains("\"expiry\":1000"));
        
        // Test JSON deserialization
        let deserialized: CacheEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, entry);
    }
}