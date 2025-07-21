use log::*;
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use std::time::Duration;
use tenant_routing_core::{
    cache::{generate_cache_key, CacheEntry},
    config::TenantRoutingConfig,
    tenant::{build_gcs_path, extract_tenant_from_host, normalize_shard_name},
};

#[no_mangle]
pub fn _start() {
    proxy_wasm::set_log_level(LogLevel::Info);
    proxy_wasm::set_root_context(|_| -> Box<dyn RootContext> { Box::new(TenantRouterRoot::new()) });
}

struct TenantRouterRoot {
    config: TenantRoutingConfig,
}

struct TenantRouter {
    config: TenantRoutingConfig,
    pending_request: Option<u32>,
    pending_default_lookup: bool,
}

impl TenantRouterRoot {
    fn new() -> Self {
        Self {
            config: TenantRoutingConfig::default(),
        }
    }
}

impl Context for TenantRouterRoot {}

impl RootContext for TenantRouterRoot {
    fn on_configure(&mut self, _config_size: usize) -> bool {
        if let Some(config_bytes) = self.get_plugin_configuration() {
            // Parse JSON config if provided
            if let Ok(config_str) = std::str::from_utf8(&config_bytes) {
                if let Ok(config_json) = serde_json::from_str::<serde_json::Value>(config_str) {
                    if let Some(bucket) = config_json.get("gcs_bucket").and_then(|v| v.as_str()) {
                        self.config.gcs_bucket = bucket.to_string();
                    }
                    if let Some(ttl) = config_json
                        .get("cache_ttl_seconds")
                        .and_then(|v| v.as_u64())
                    {
                        self.config.cache_ttl_seconds = ttl;
                    }
                    if let Some(shard) = config_json.get("default_shard").and_then(|v| v.as_str()) {
                        self.config.default_shard = shard.to_string();
                    }
                }
            }
        }
        true
    }

    fn create_http_context(&self, _context_id: u32) -> Option<Box<dyn HttpContext>> {
        Some(Box::new(TenantRouter {
            config: self.config.clone(),
            pending_request: None,
            pending_default_lookup: false,
        }))
    }

    fn get_type(&self) -> Option<ContextType> {
        Some(ContextType::HttpContext)
    }
}

impl Context for TenantRouter {
    fn on_http_call_response(
        &mut self,
        _token_id: u32,
        _num_headers: usize,
        body_size: usize,
        _num_trailers: usize,
    ) {
        if let Some(body) = self.get_http_call_response_body(0, body_size) {
            if let Ok(shard) = std::str::from_utf8(&body) {
                let shard = shard.trim();

                // Determine which tenant we're caching for
                let cache_tenant = if self.pending_default_lookup {
                    "default".to_string()
                } else if let (Some(tenant), _) = self.get_shared_data("pending_tenant") {
                    if let Ok(tenant_str) = std::str::from_utf8(&tenant) {
                        tenant_str.to_string()
                    } else {
                        String::new()
                    }
                } else {
                    String::new()
                };

                if !cache_tenant.is_empty() {
                    // Store in cache
                    let current_time = self
                        .get_current_time()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs();

                    let cache_entry = CacheEntry::with_ttl(
                        normalize_shard_name(shard),
                        current_time,
                        self.config.cache_ttl_seconds,
                    );

                    if let Ok(serialized) = serde_json::to_vec(&cache_entry) {
                        if let Err(e) = self.set_shared_data(
                            &generate_cache_key(&cache_tenant),
                            Some(&serialized),
                            None,
                        ) {
                            warn!("Failed to cache tenant {}: {:?}", cache_tenant, e);
                        }
                    }

                    info!("Cached tenant {} -> {}", cache_tenant, shard);
                }

                // Continue the request with the shard
                self.set_shard_headers(shard);
                self.resume_http_request();

                return;
            }
        }

        // On error, try to look up /default/shard if this wasn't already a default lookup
        if !self.pending_default_lookup {
            warn!("Failed to get shard from GCS, trying /default/shard");
            self.pending_default_lookup = true;

            match self.lookup_tenant_shard("default") {
                Ok(Some(shard)) => {
                    // Found in cache
                    self.set_shard_headers(&shard);
                    self.resume_http_request();
                }
                Ok(None) => {
                    // Failed to dispatch, use configured default
                    warn!("Failed to dispatch /default/shard request, using configured default");
                    self.set_shard_headers(&self.config.default_shard);
                    self.resume_http_request();
                }
                Err(_) => {
                    // Lookup dispatched, will come back here
                }
            }
        } else {
            // Use configured default as final fallback
            warn!(
                "Using configured default shard: {}",
                self.config.default_shard
            );
            self.set_shard_headers(&self.config.default_shard);
            self.resume_http_request();
        }
    }
}

impl HttpContext for TenantRouter {
    fn on_http_request_headers(&mut self, _num_headers: usize, _end_of_stream: bool) -> Action {
        // Extract tenant from hostname
        let authority = self
            .get_http_request_header(":authority")
            .unwrap_or_default();

        let tenant = extract_tenant_from_host(&authority).unwrap_or_else(|| "default".to_string());

        // Store tenant for use in callback
        if let Err(e) = self.set_shared_data("pending_tenant", Some(tenant.as_bytes()), None) {
            warn!("Failed to set shared data for pending_tenant: {:?}", e);
        }

        // Try to look up the tenant's shard
        match self.lookup_tenant_shard(&tenant) {
            Ok(Some(shard)) => {
                // Found in cache
                self.set_shard_headers(&shard);
                Action::Continue
            }
            Ok(None) => {
                // Failed to dispatch request, try default
                self.pending_default_lookup = true;
                match self.lookup_tenant_shard("default") {
                    Ok(Some(shard)) => {
                        self.set_shard_headers(&shard);
                        Action::Continue
                    }
                    Ok(None) => {
                        // Failed to dispatch default lookup too
                        warn!(
                            "Failed to dispatch /default/shard request, using configured default"
                        );
                        self.set_shard_headers(&self.config.default_shard);
                        Action::Continue
                    }
                    Err(action) => action, // Paused for lookup
                }
            }
            Err(action) => action, // Paused for lookup
        }
    }
}

impl TenantRouter {
    fn set_shard_headers(&self, shard: &str) {
        // Remove any existing header first
        self.set_http_request_header("x-tenant-shard", None);
        self.set_http_request_header("x-tenant-shard", Some(shard));

        if let Some(tenant) = self.get_http_request_header(":authority") {
            if let Some(dot_pos) = tenant.find('.') {
                self.set_http_request_header("x-tenant-name", Some(&tenant[..dot_pos]));
            }
        }
    }

    fn dispatch_gcs_lookup(&mut self, path: &str) -> Result<u32, Status> {
        let headers = vec![
            (":method", "GET"),
            (":path", path),
            (":authority", "localhost:8080"),
            (":scheme", "http"),
        ];

        self.dispatch_http_call("gcs_proxy", headers, None, vec![], Duration::from_secs(5))
    }

    fn lookup_tenant_shard(&mut self, tenant: &str) -> Result<Option<String>, Action> {
        // Check cache first
        let cache_key = generate_cache_key(tenant);

        if let (Some(cached_data), _) = self.get_shared_data(&cache_key) {
            if let Ok(cache_str) = std::str::from_utf8(&cached_data) {
                if let Ok(cache_entry) = serde_json::from_str::<CacheEntry>(cache_str) {
                    let now = self
                        .get_current_time()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs();

                    if cache_entry.is_valid(now) {
                        info!(
                            "Using cached shard for tenant {}: {}",
                            tenant, cache_entry.shard
                        );
                        return Ok(Some(cache_entry.shard));
                    }
                }
            }
        }

        // Not in cache, need to look it up
        let path = build_gcs_path(&self.config.gcs_bucket, tenant);

        match self.dispatch_gcs_lookup(&path) {
            Ok(token) => {
                self.pending_request = Some(token);
                info!("Looking up tenant {} in GCS", tenant);
                Err(Action::Pause)
            }
            Err(e) => {
                warn!(
                    "Failed to dispatch GCS request for tenant {}: {:?}",
                    tenant, e
                );
                Ok(None)
            }
        }
    }
}
