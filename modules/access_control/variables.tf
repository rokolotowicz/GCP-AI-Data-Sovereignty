variable "project_id" {
  type = string
}

variable "finance_key_id" {
  type = string
}

variable "marketing_key_id" {
  type = string
}

variable "dataflow_worker_sa" {
  type = string
}

variable "finance_sa" {
  type = string
}

variable "marketing_sa" {
  type = string
}

variable "admin_sa" {
  type = string
}

variable "vectors_bucket" {
  description = "Bucket holding the LanceDB dataset"
  type        = string
}
