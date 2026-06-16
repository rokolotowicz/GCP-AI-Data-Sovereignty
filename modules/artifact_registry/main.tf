# ---------------------------------------------------------------------------
# Provision the Artifact Registry service agent first, then grant KEK access.
# The AR agent is otherwise only auto-created when the first repo is made, but
# a CMEK repo needs the agent to already hold key access -> chicken/egg.
# ---------------------------------------------------------------------------
resource "google_project_service_identity" "artifactregistry" {
  provider = google-beta
  project  = var.project_id
  service  = "artifactregistry.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "ar_cmek" {
  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.artifactregistry.email}"
}

resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = "sovereign-ai"
  description   = "Container images for Sovereign-AI Presidio service"
  format        = "DOCKER"
  project       = var.project_id

  kms_key_name = var.kms_key_id
  labels       = var.labels

  depends_on = [google_kms_crypto_key_iam_member.ar_cmek]
}

resource "google_artifact_registry_repository_iam_member" "cr_pull" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.cloud_run_sa}"
}
