terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

locals {
  labels = {
    project     = "sovereign-ai"
    environment = var.env
    managed-by  = "terraform"
    data-class  = "pii-high"
  }
}

# ---------------------------------------------------------------------------
# Enable required APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "services" {
  for_each = toset([
    "cloudkms.googleapis.com",
    "dataflow.googleapis.com",
    "compute.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "config.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Shared foundation (reused from the batch design)
# ---------------------------------------------------------------------------
module "kms" {
  source     = "./modules/kms"
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  depends_on = [google_project_service.services]
}

module "iam" {
  source         = "./modules/iam"
  project_id     = var.project_id
  project_number = var.project_number

  depends_on = [google_project_service.services]
}

module "gcs" {
  source         = "./modules/gcs"
  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region
  kms_key_id     = module.kms.crypto_key_id
  cloud_run_sa   = module.iam.dataflow_worker_sa_email # worker reads raw / writes cleaned
  bucket_prefix  = var.bucket_prefix
  labels         = local.labels

  depends_on = [module.kms, module.iam]
}

module "artifact_registry" {
  source         = "./modules/artifact_registry"
  project_id     = var.project_id
  project_number = var.project_number
  region         = var.region
  kms_key_id     = module.kms.crypto_key_id
  cloud_run_sa   = module.iam.dataflow_worker_sa_email # worker pulls the Flex Template image
  labels         = local.labels

  depends_on = [module.kms, module.iam]
}

# ---------------------------------------------------------------------------
# Streaming path: GCS notify -> Pub/Sub -> Confidential Dataflow
# ---------------------------------------------------------------------------
module "pubsub" {
  source             = "./modules/pubsub"
  project_id         = var.project_id
  project_number     = var.project_number
  kms_key_id         = module.kms.crypto_key_id
  raw_bucket         = module.gcs.raw_bucket_name
  dataflow_worker_sa = module.iam.dataflow_worker_sa_email
  labels             = local.labels

  depends_on = [module.gcs, module.iam]
}

module "dataflow" {
  source                 = "./modules/dataflow"
  project_id             = var.project_id
  project_number         = var.project_number
  region                 = var.region
  job_name               = "pii-streaming-scrubber"
  template_spec_gcs_path = var.dataflow_template_spec # "" until Beam container built
  dataflow_worker_sa     = module.iam.dataflow_worker_sa_email
  input_subscription     = module.pubsub.subscription_id
  cleaned_bucket         = module.gcs.cleaned_bucket_name
  vectors_bucket         = module.gcs.vectors_bucket_name
  staging_bucket         = module.gcs.dataflow_bucket_name
  image_repo_url         = module.artifact_registry.repository_url
  image_tag              = var.dataflow_image_tag
  kms_key_id             = module.kms.crypto_key_id
  finance_key_id         = module.kms.field_key_finance_id
  marketing_key_id       = module.kms.field_key_marketing_id
  labels                 = local.labels

  depends_on = [module.pubsub, module.artifact_registry, module.access_control]
}

# ---------------------------------------------------------------------------
# Field-Level Encryption access matrix (finance / marketing / admin)
# ---------------------------------------------------------------------------
module "access_control" {
  source             = "./modules/access_control"
  project_id         = var.project_id
  finance_key_id     = module.kms.field_key_finance_id
  marketing_key_id   = module.kms.field_key_marketing_id
  dataflow_worker_sa = module.iam.dataflow_worker_sa_email
  finance_sa         = module.iam.finance_sa_email
  marketing_sa       = module.iam.marketing_sa_email
  admin_sa           = module.iam.admin_sa_email
  vectors_bucket     = module.gcs.vectors_bucket_name

  depends_on = [module.kms, module.iam, module.gcs]
}

# ---------------------------------------------------------------------------
# NOTE: the Cloud Run module from the batch design is retained in
# ./modules/cloud_run for reference but is NOT composed here. The streaming
# (Dataflow) path supersedes it. Re-add a module block if you want both.
# ---------------------------------------------------------------------------
