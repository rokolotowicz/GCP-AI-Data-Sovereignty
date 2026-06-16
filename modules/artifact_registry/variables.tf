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
  type = string
}

variable "cloud_run_sa" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
