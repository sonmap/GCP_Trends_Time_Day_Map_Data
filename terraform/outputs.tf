output "collector_service_url" {
  description = "Cloud Run collector service URL"
  value       = google_cloud_run_v2_service.collector.uri
}

output "raw_bucket" {
  description = "Cloud Storage raw bucket name"
  value       = google_storage_bucket.raw.name
}

output "collector_service_account" {
  description = "Cloud Run collector service account"
  value       = google_service_account.collector.email
}
