# ---------------------------------------------------------------------------
# Service accounts
# ---------------------------------------------------------------------------
resource "google_service_account" "cloud_run" {
  account_id   = "presidio-redactor-sa"
  display_name = "Presidio Redactor (Cloud Run)"
  description  = "Identity for the Presidio PII-redaction Cloud Run service"
  project      = var.project_id
}

resource "google_service_account" "eventarc" {
  account_id   = "eventarc-trigger-sa"
  display_name = "Eventarc Trigger"
  description  = "Identity used by Eventarc to invoke the Cloud Run service"
  project      = var.project_id
}

# Dataflow worker identity (the confidential streaming pipeline runs as this).
resource "google_service_account" "dataflow_worker" {
  account_id   = "dataflow-worker-sa"
  display_name = "Dataflow Confidential Worker"
  description  = "Identity for the confidential PII-scrubbing Dataflow workers"
  project      = var.project_id
}

# Dataflow workers need the worker role to talk to the Dataflow service.
resource "google_project_iam_member" "dataflow_worker_role" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

# Reuse the same least-privilege processor role (storage + KMS use + logging).
resource "google_project_iam_member" "dataflow_worker_custom" {
  project = var.project_id
  role    = google_project_iam_custom_role.processor.id
  member  = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

# ---------------------------------------------------------------------------
# Custom least-privilege role for the redactor worker.
# NOTE: deliberately NO KMS permissions here. Granting cryptoKey use at the
# PROJECT level would let the worker touch every key and defeat the
# field-level crypto-segregation. KMS access is granted per-key, per-identity
# in the access_control module instead.
# ---------------------------------------------------------------------------
resource "google_project_iam_custom_role" "processor" {
  role_id     = "sovereignAiProcessor"
  title       = "Sovereign-AI PII Processor"
  description = "Least-privilege role for the redactor worker (storage + logging only)"
  project     = var.project_id
  permissions = [
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.create",
    "logging.logEntries.create",
  ]
}

resource "google_project_iam_member" "cloud_run_custom" {
  project = var.project_id
  role    = google_project_iam_custom_role.processor.id
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ---------------------------------------------------------------------------
# Eventarc trigger permissions
# ---------------------------------------------------------------------------
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

resource "google_project_iam_member" "eventarc_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

# NOTE: the GCS notification service agent (gs-project-accounts) needs
# roles/pubsub.publisher to publish object-finalized events. That binding now
# lives in the gcs module, where it references the storage data source that
# PROVISIONS the agent first (hardcoding the email here bound it before it
# existed -> 400 "does not exist").

# ---------------------------------------------------------------------------
# Consumer identities (the "need-to-know" tenants). These read the LanceDB
# dataset and attempt field decryption. What each can actually decrypt is
# decided by per-key IAM in the access_control module.
# ---------------------------------------------------------------------------
resource "google_service_account" "finance" {
  account_id   = "consumer-finance-sa"
  display_name = "Finance Consumer"
  description  = "Finance need-to-know identity (may decrypt SSN field)"
  project      = var.project_id
}

resource "google_service_account" "marketing" {
  account_id   = "consumer-marketing-sa"
  display_name = "Marketing Consumer"
  description  = "Marketing need-to-know identity (may decrypt address field)"
  project      = var.project_id
}

resource "google_service_account" "admin" {
  account_id   = "consumer-admin-sa"
  display_name = "Admin Consumer"
  description  = "Admin identity: can search the index, decrypts no PII"
  project      = var.project_id
}
