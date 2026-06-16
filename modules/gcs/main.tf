# ---------------------------------------------------------------------------
# Allow the GCS service agent to use the KEK for CMEK encryption.
# ---------------------------------------------------------------------------
data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gcs_cmek" {
  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

# The GCS notification agent (same gs-project-accounts SA) must be able to
# publish object-finalized events to Pub/Sub. Referencing the data source email
# guarantees the agent is provisioned before this binding runs.
resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

# ---------------------------------------------------------------------------
# Raw landing bucket - source files with PII land here
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "raw" {
  name                        = "${var.bucket_prefix}-raw"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # POC; flip to false for prod

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  labels = merge(var.labels, { bucket-purpose = "raw-pii" })

  # Auto-delete raw files after 30 days to reduce blast radius
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# ---------------------------------------------------------------------------
# Cleaned (redacted) output bucket
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "cleaned" {
  name                        = "${var.bucket_prefix}-cleaned"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  labels = merge(var.labels, { bucket-purpose = "redacted-output" })

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# ---------------------------------------------------------------------------
# Vectors bucket - holds the LanceDB dataset (vectors + redacted text +
# per-field ciphertext columns). CMEK at rest with the HSM KEK.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "vectors" {
  name                        = "${var.bucket_prefix}-vectors"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  labels = merge(var.labels, { bucket-purpose = "lancedb-vectors" })

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# Worker writes the LanceDB dataset.
resource "google_storage_bucket_iam_member" "cr_vectors_write" {
  bucket = google_storage_bucket.vectors.name
  role   = "roles/storage.objectAdmin" # LanceDB needs create+overwrite+delete on manifests
  member = "serviceAccount:${var.cloud_run_sa}"
}

# ---------------------------------------------------------------------------
# Dataflow staging/temp bucket. Holds:
#   - the published Flex Template spec (templates/pii-scrubber.json), written
#     by the build script (gcloud), so the bucket must exist on first apply
#   - Dataflow staging files (graph) and temp files (execution)
# CMEK at rest with the HSM KEK, like every other bucket here.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "dataflow" {
  name                        = "${var.bucket_prefix}-dataflow"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  labels = merge(var.labels, { bucket-purpose = "dataflow-staging" })

  # Dataflow temp artifacts are transient; clean them up.
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["temp/", "staging/"]
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

# Worker SA needs read+write on staging/temp during job execution.
resource "google_storage_bucket_iam_member" "worker_dataflow_admin" {
  bucket = google_storage_bucket.dataflow.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.cloud_run_sa}"
}

# ---------------------------------------------------------------------------
# Bucket-scoped IAM for the Cloud Run service account
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "cr_raw_read" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.cloud_run_sa}"
}

resource "google_storage_bucket_iam_member" "cr_cleaned_write" {
  bucket = google_storage_bucket.cleaned.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.cloud_run_sa}"
}
