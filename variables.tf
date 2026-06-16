variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "sovereign-ai-499423"
}

variable "project_number" {
  description = "GCP project number (used to construct service agent emails)"
  type        = string
  default     = "142959187197"
}

variable "region" {
  description = "GCP region for all regional resources"
  type        = string
  default     = "us-central1"
}

variable "env" {
  description = "Environment label"
  type        = string
  default     = "poc"
}

variable "bucket_prefix" {
  description = "Prefix for GCS bucket names (must be globally unique)"
  type        = string
  default     = "sovereign-ai-499423"
}

variable "cloud_run_image" {
  description = "Container image for the Presidio service. Placeholder until image is built and pushed to Artifact Registry."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "dataflow_template_spec" {
  description = <<-EOT
    GCS path to the published Flex Template spec for the confidential PII
    scrubber. Leave "" until the Beam container is built and the spec is
    published; the Dataflow job is only created once this is set.
    Example: gs://sovereign-ai-499423-dataflow/templates/pii-scrubber.json
  EOT
  type        = string
  default     = ""
}

variable "dataflow_image_tag" {
  description = "Tag of the pii-scrubber image the build script pushed (must match)."
  type        = string
  default     = "v1"
}
