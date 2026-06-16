variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}

variable "region" {
  type = string
}

variable "service_name" {
  type = string
}

variable "image" {
  description = "Container image URI"
  type        = string
}

variable "service_account" {
  description = "Email of the SA used as the service identity"
  type        = string
}

variable "raw_bucket" {
  type = string
}

variable "cleaned_bucket" {
  type = string
}

variable "eventarc_sa" {
  description = "Email of the SA used by the Eventarc trigger"
  type        = string
}

variable "labels" {
  type    = map(string)
  default = {}
}
