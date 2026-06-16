variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "raw_bucket" {
  description = "Name of the raw landing bucket that emits notifications"
  type        = string
}

variable "dataflow_worker_sa" {
  description = "Email of the Dataflow worker SA that subscribes to the topic"
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
