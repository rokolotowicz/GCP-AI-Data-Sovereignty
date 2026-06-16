output "cloud_run_sa_email" {
  value = google_service_account.cloud_run.email
}

output "eventarc_sa_email" {
  value = google_service_account.eventarc.email
}

output "dataflow_worker_sa_email" {
  value = google_service_account.dataflow_worker.email
}

output "finance_sa_email" {
  value = google_service_account.finance.email
}

output "marketing_sa_email" {
  value = google_service_account.marketing.email
}

output "admin_sa_email" {
  value = google_service_account.admin.email
}

output "custom_role_id" {
  value = google_project_iam_custom_role.processor.id
}
