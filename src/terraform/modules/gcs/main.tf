# GCS bucket for tenant-shard mappings
resource "google_storage_bucket" "tenant_mappings" {
  name     = "${var.project_id}-tenant-shard-mapping"
  location = var.region
  
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

# Service account for Envoy to access GCS
resource "google_service_account" "envoy_gcs_reader" {
  account_id   = "${var.name_prefix}-envoy-gcs"
  display_name = "Envoy GCS Reader"
  description  = "Service account for Envoy to read tenant mappings from GCS"
}

# Grant the service account permission to read from the bucket
resource "google_storage_bucket_iam_member" "envoy_reader" {
  bucket = google_storage_bucket.tenant_mappings.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.envoy_gcs_reader.email}"
}

# Grant the service account permission to pull from GCR
resource "google_project_iam_member" "envoy_gcr_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.envoy_gcs_reader.email}"
}

