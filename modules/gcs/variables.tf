variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "region" {
  type = string
}

variable "kms_key_id" {
  description = "Fully qualified KEK ID used as CMEK default for both buckets"
  type        = string
}

variable "cloud_run_sa" {
  description = "Email of the Cloud Run service account that needs bucket access"
  type        = string
}

variable "bucket_prefix" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
