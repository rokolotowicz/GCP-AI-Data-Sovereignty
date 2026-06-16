output "service_name" {
  value = google_cloud_run_v2_service.main.name
}

output "service_url" {
  value = google_cloud_run_v2_service.main.uri
}

output "trigger_name" {
  value = google_eventarc_trigger.gcs_finalize.name
}
