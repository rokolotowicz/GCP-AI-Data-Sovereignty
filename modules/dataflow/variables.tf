variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "job_name" {
  type    = string
  default = "pii-streaming-scrubber"
}

variable "template_spec_gcs_path" {
  description = <<-EOT
    GCS path to the published Flex Template spec JSON
    (e.g. gs://<bucket>/templates/pii-scrubber.json).
    Leave "" until the Beam container is built; the job is not created while empty.
  EOT
  type        = string
  default     = ""
}

variable "dataflow_worker_sa" {
  description = "Email of the Dataflow worker service account"
  type        = string
}

variable "input_subscription" {
  description = "Full Pub/Sub subscription path the job reads from"
  type        = string
}

variable "cleaned_bucket" {
  description = "Bucket where redacted output is written"
  type        = string
}

variable "vectors_bucket" {
  description = "Bucket holding the LanceDB dataset"
  type        = string
}

variable "finance_key_id" {
  description = "HSM key used to encrypt finance-domain fields (SSN)"
  type        = string
}

variable "marketing_key_id" {
  description = "HSM key used to encrypt marketing-domain fields (address)"
  type        = string
}

variable "staging_bucket" {
  description = "Bucket for Dataflow staging/temp (and the Flex Template spec)"
  type        = string
}

variable "image_repo_url" {
  description = "Artifact Registry repo URL, e.g. us-central1-docker.pkg.dev/PROJECT/sovereign-ai"
  type        = string
}

variable "image_name" {
  description = "Worker/launcher image name"
  type        = string
  default     = "pii-scrubber"
}

variable "image_tag" {
  description = "Worker/launcher image tag (must match what the build script pushed)"
  type        = string
  default     = "v1"
}

variable "kms_key_id" {
  description = "HSM-backed KEK used for Dataflow CMEK"
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "project_number" {
  description = "GCP project number (for Compute/Dataflow service-agent emails)"
  type        = string
}
