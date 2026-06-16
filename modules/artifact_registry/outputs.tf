output "repository_id" {
  value = google_artifact_registry_repository.main.repository_id
}

output "repository_url" {
  description = "Docker push/pull URL for the repo"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
}
