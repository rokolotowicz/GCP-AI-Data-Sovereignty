# ---------------------------------------------------------------------------
# Pub/Sub service agent must be able to use the KEK for CMEK on the topic.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Provision the Pub/Sub service agent first, then grant it KEK access.
# Hardcoding service-<num>@gcp-sa-pubsub... and binding before the agent
# exists fails with 400 "does not exist" on a fresh project.
# ---------------------------------------------------------------------------
resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "pubsub_cmek" {
  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.pubsub.email}"
}

# ---------------------------------------------------------------------------
# Topic that receives GCS object-finalized notifications (CMEK-encrypted).
# ---------------------------------------------------------------------------
resource "google_pubsub_topic" "ingest" {
  name         = "sovereign-ai-ingest"
  project      = var.project_id
  kms_key_name = var.kms_key_id
  labels       = var.labels

  message_retention_duration = "86400s" # 24h

  depends_on = [google_kms_crypto_key_iam_member.pubsub_cmek]
}

# ---------------------------------------------------------------------------
# GCS -> Pub/Sub notification: "a new file landed in raw bucket".
# The GCS service agent needs pubsub.publisher (granted in the iam module).
# ---------------------------------------------------------------------------
resource "google_storage_notification" "raw_finalize" {
  bucket         = var.raw_bucket
  topic          = google_pubsub_topic.ingest.id
  payload_format = "JSON_API_V1"
  event_types    = ["OBJECT_FINALIZE"]
}

# ---------------------------------------------------------------------------
# Subscription the Dataflow streaming job reads from.
# ---------------------------------------------------------------------------
resource "google_pubsub_subscription" "dataflow" {
  name    = "sovereign-ai-ingest-dataflow"
  topic   = google_pubsub_topic.ingest.id
  project = var.project_id
  labels  = var.labels

  ack_deadline_seconds       = 120
  message_retention_duration = "86400s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = "" # never expire (streaming job long-lived)
  }
}

# Allow the Dataflow worker SA to consume the subscription.
resource "google_pubsub_subscription_iam_member" "dataflow_subscriber" {
  subscription = google_pubsub_subscription.dataflow.name
  project      = var.project_id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.dataflow_worker_sa}"
}
