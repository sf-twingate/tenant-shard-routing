use alloc::format;
use alloc::string::{String, ToString};
use alloc::vec::Vec;

/// Extract tenant name from hostname
///
/// # Examples
/// - "tenant1.example.com" -> Some("tenant1")
/// - "tenant1.example.com:8080" -> Some("tenant1")
/// - "localhost" -> None
/// - "192.168.1.1" -> None
pub fn extract_tenant_from_host(host: &str) -> Option<String> {
    let host_without_port = host.split(':').next().unwrap_or(host);

    if is_ip_address(host_without_port) {
        return None;
    }

    let parts: Vec<&str> = host_without_port.split('.').collect();

    if parts.len() >= 2 {
        let tenant = parts[0];

        if is_valid_tenant_name(tenant) {
            Some(tenant.to_string())
        } else {
            None
        }
    } else {
        None
    }
}

fn is_ip_address(s: &str) -> bool {
    s.split('.').all(|part| part.parse::<u32>().is_ok())
}

fn is_valid_tenant_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_')
}

/// Build GCS path for tenant shard mapping
///
/// # Example
/// ```
/// use tenant_routing_core::tenant::build_gcs_path;
/// assert_eq!(build_gcs_path("my-bucket", "tenant1"), "/my-bucket/tenant1/shard");
/// ```
pub fn build_gcs_path(bucket: &str, tenant: &str) -> String {
    format!("/{}/{}/shard", bucket, tenant)
}

/// Build the object name for GCS (without leading slash)
///
/// # Example
/// ```
/// use tenant_routing_core::tenant::build_gcs_object_name;
/// assert_eq!(build_gcs_object_name("tenant1"), "tenant1/shard");
/// ```
pub fn build_gcs_object_name(tenant: &str) -> String {
    format!("{}/shard", tenant)
}

pub fn normalize_shard_name(shard: &str) -> String {
    shard.trim().to_lowercase()
}
