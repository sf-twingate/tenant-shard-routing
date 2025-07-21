use anyhow::Result;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use google_cloud_storage::{
    client::{Client, ClientConfig},
    http::objects::{download::Range, get::GetObjectRequest},
};
use moka::future::Cache;
use serde::{Deserialize, Serialize};
use std::{env, sync::Arc, time::Duration};
use tenant_routing_core::{
    config::TenantRoutingConfig,
    tenant::{build_gcs_object_name, extract_tenant_from_host, normalize_shard_name},
};
use tower_http::trace::TraceLayer;
use tracing::{error, info, Level};

#[derive(Clone)]
struct AppState {
    gcs_client: Arc<Client>,
    config: TenantRoutingConfig,
    cache: Cache<String, String>,
}

#[derive(Deserialize)]
struct LookupParams {
    host: String,
}

#[derive(Serialize)]
struct LookupResponse {
    shard: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    tenant: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive(Level::INFO.into()),
        )
        .init();

    // Get configuration from environment
    let bucket_name = env::var("GCS_BUCKET").unwrap_or_else(|_| "tenant-routing-data".to_string());
    let default_shard = env::var("DEFAULT_SHARD").unwrap_or_else(|_| "shard1".to_string());
    let cache_ttl_seconds = env::var("CACHE_TTL")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(300);

    let port = env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8080);

    let config = TenantRoutingConfig::new(bucket_name, cache_ttl_seconds, default_shard);

    info!("Initializing tenant lookup service");
    info!("GCS bucket: {}", config.gcs_bucket);
    info!("Default shard: {}", config.default_shard);
    info!("Cache TTL: {}s", config.cache_ttl_seconds);
    info!("Port: {}", port);

    // Initialize GCS client
    let gcs_config = ClientConfig::default().with_auth().await?;
    let gcs_client = Arc::new(Client::new(gcs_config));

    // Initialize cache
    let cache = Cache::builder()
        .time_to_live(Duration::from_secs(config.cache_ttl_seconds))
        .max_capacity(10_000)
        .build();

    let state = AppState {
        gcs_client,
        config,
        cache,
    };

    let app = Router::new()
        .route("/lookup", get(lookup_tenant))
        .route("/health", get(health_check))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;

    info!("Server listening on {}", listener.local_addr()?);

    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}

async fn lookup_tenant(
    Query(params): Query<LookupParams>,
    State(state): State<AppState>,
) -> Result<Json<LookupResponse>, StatusCode> {
    let host = params.host;
    let tenant = extract_tenant_from_host(&host);

    match tenant {
        Some(tenant_name) => {
            // Check cache first
            if let Some(cached_shard) = state.cache.get(&tenant_name).await {
                info!("Cache hit for tenant: {} -> {}", tenant_name, cached_shard);

                return Ok(Json(LookupResponse {
                    shard: cached_shard,
                    tenant: Some(tenant_name),
                }));
            }

            // Fetch from GCS
            match fetch_tenant_mapping(&state.gcs_client, &state.config.gcs_bucket, &tenant_name)
                .await
            {
                Ok(shard) => {
                    let normalized_shard = normalize_shard_name(&shard);

                    info!(
                        "GCS lookup for tenant: {} -> {}",
                        tenant_name, normalized_shard
                    );

                    state
                        .cache
                        .insert(tenant_name.clone(), normalized_shard.clone())
                        .await;

                    Ok(Json(LookupResponse {
                        shard: normalized_shard,
                        tenant: Some(tenant_name),
                    }))
                }
                Err(e) => {
                    error!("Failed to fetch tenant mapping for {}: {}", tenant_name, e);

                    Ok(Json(LookupResponse {
                        shard: state.config.default_shard.clone(),
                        tenant: Some(tenant_name),
                    }))
                }
            }
        }
        None => {
            info!(
                "No tenant extracted from host: {}, using default shard",
                host
            );
            Ok(Json(LookupResponse {
                shard: state.config.default_shard.clone(),
                tenant: None,
            }))
        }
    }
}

async fn fetch_tenant_mapping(client: &Client, bucket: &str, tenant: &str) -> Result<String> {
    let object_name = build_gcs_object_name(tenant);

    let request = GetObjectRequest {
        bucket: bucket.to_string(),
        object: object_name.clone(),
        ..Default::default()
    };

    match client.get_object(&request).await {
        Ok(_) => {
            let bytes = client.download_object(&request, &Range::default()).await?;
            let shard = String::from_utf8(bytes)?.trim().to_string();
            Ok(shard)
        }
        Err(_) => Err(anyhow::anyhow!("Tenant mapping not found")),
    }
}
