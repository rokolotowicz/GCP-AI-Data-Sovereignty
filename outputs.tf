output "raw_bucket" {
  description = "Bucket where source files (PDF/Word/Excel/CSV/scans) land"
  value       = module.gcs.raw_bucket_name
}

output "cleaned_bucket" {
  description = "Bucket where redacted output is written"
  value       = module.gcs.cleaned_bucket_name
}

output "kms_key_id" {
  description = "HSM-backed KEK resource ID"
  value       = module.kms.crypto_key_id
}

output "ingest_topic" {
  description = "Pub/Sub topic receiving GCS object-finalized notifications"
  value       = module.pubsub.topic_name
}

output "dataflow_subscription" {
  description = "Subscription the confidential Dataflow job reads from"
  value       = module.pubsub.subscription_name
}

output "dataflow_worker_sa" {
  description = "Service account the confidential Dataflow workers run as"
  value       = module.iam.dataflow_worker_sa_email
}

output "artifact_registry_repo" {
  description = "Docker repo for the Beam/Flex-Template container image"
  value       = module.artifact_registry.repository_url
}

output "dataflow_job_state" {
  description = "State of the streaming job (not-created until spec published)"
  value       = module.dataflow.job_state
}

output "vectors_bucket" {
  description = "Bucket holding the LanceDB dataset (CMEK)"
  value       = module.gcs.vectors_bucket_name
}

output "field_key_finance" {
  description = "HSM key for finance-domain field encryption (SSN)"
  value       = module.kms.field_key_finance_id
}

output "field_key_marketing" {
  description = "HSM key for marketing-domain field encryption (address)"
  value       = module.kms.field_key_marketing_id
}

output "consumer_finance_sa" {
  value = module.iam.finance_sa_email
}

output "consumer_marketing_sa" {
  value = module.iam.marketing_sa_email
}

output "consumer_admin_sa" {
  value = module.iam.admin_sa_email
}

output "fle_access_matrix" {
  description = "Who can decrypt what"
  value       = module.access_control.access_matrix
}

output "dataflow_staging_bucket" {
  description = "Bucket for Dataflow staging/temp and the Flex Template spec"
  value       = module.gcs.dataflow_bucket_name
}
