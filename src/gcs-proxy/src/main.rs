use anyhow::Result;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Response,
    routing::get,
    Router,
};
use google_cloud_storage::{
    client::{Client, ClientConfig},
    http::objects::{download::Range, get::GetObjectRequest},
};
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use tracing::{error, info, Level};

#[derive(Clone)]
struct AppState {
    gcs_client: Arc<Client>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(Level::INFO.into()),
        )
        .init();

    info!("Initializing GCS proxy service");

    // Initialize GCS client with default credentials
    let config = ClientConfig::default().with_auth().await?;
    let gcs_client = Arc::new(Client::new(config));

    let state = AppState { gcs_client };

    // Build router
    let app = Router::new()
        .route("/gcs/*path", get(proxy_gcs_request))
        .route("/health", get(health_check))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    info!("GCS proxy listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}

async fn proxy_gcs_request(
    Path(path): Path<String>,
    State(state): State<AppState>,
) -> Result<Response<String>, StatusCode> {
    let parts: Vec<&str> = path.splitn(2, '/').collect();

    if parts.len() != 2 {
        error!("Invalid GCS path format: {}", path);
        return Err(StatusCode::BAD_REQUEST);
    }

    let bucket = parts[0];
    let object = parts[1];

    info!("Proxying request for gs://{}/{}", bucket, object);

    // Create request
    let request = GetObjectRequest {
        bucket: bucket.to_string(),
        object: object.to_string(),
        ..Default::default()
    };

    // Try to fetch the object
    match state.gcs_client.get_object(&request).await {
        Ok(_metadata) => {
            // Download the object content
            match state
                .gcs_client
                .download_object(&request, &Range::default())
                .await
            {
                Ok(bytes) => {
                    match String::from_utf8(bytes) {
                        Ok(content) => {
                            info!("Successfully fetched gs://{}/{}", bucket, object);
                            Ok(Response::builder()
                                .status(StatusCode::OK)
                                .header("Content-Type", "text/plain")
                                .body(content)
                                .unwrap())
                        }
                        Err(e) => {
                            error!("Content is not valid UTF-8: {}", e);
                            // Return raw bytes as base64 or handle binary content
                            Err(StatusCode::INTERNAL_SERVER_ERROR)
                        }
                    }
                }
                Err(e) => {
                    error!("Failed to download object content: {}", e);
                    Err(StatusCode::INTERNAL_SERVER_ERROR)
                }
            }
        }
        Err(e) => {
            error!("Failed to get object metadata: {}", e);
            if e.to_string().contains("404") || e.to_string().contains("not found") {
                Err(StatusCode::NOT_FOUND)
            } else {
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }
}