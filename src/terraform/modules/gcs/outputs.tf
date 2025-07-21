output "bucket_name" {
  description = "GCS bucket containing tenant-shard mappings"
  value       = google_storage_bucket.tenant_mappings.name
}

output "bucket_url" {
  description = "GCS bucket URL for tenant mappings"
  value       = google_storage_bucket.tenant_mappings.url
}

output "service_account_email" {
  description = "Service account email for Envoy GCS access"
  value       = google_service_account.envoy_gcs_reader.email
}

output "service_account_id" {
  description = "Service account ID for Envoy GCS access"
  value       = google_service_account.envoy_gcs_reader.id
}