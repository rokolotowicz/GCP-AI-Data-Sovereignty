# ===========================================================================
# Confidential Dataflow streaming job (Flex Template).
#
# Why Flex Template (not google_dataflow_job + a Google template):
#   The pipeline runs CUSTOM code (Tesseract OCR -> text extraction ->
#   Presidio redaction -> chunk/embed). Stock Google-provided templates
#   cannot run that. A Flex Template packages our own container + spec.
#
# How "encryption in use" is actually achieved:
#   1. additional_experiments = ["enable_confidential_compute"]
#      -> verified Dataflow SERVICE OPTION (passed via additional-experiments).
#   2. machine_type = "n2d-standard-2"
#      -> N2D is required for AMD SEV to physically engage. The service
#         option WITHOUT an N2D machine type does NOT give you a TEE.
#   Both conditions must hold or the confidentiality claim is false.
#
# Gating:
#   This resource only creates once var.template_spec_gcs_path is set to a
#   REAL published Flex Template spec. Until then it is count=0 so the rest
#   of the infra (Pub/Sub, buckets, SAs, KMS) applies cleanly. The spec is
#   published when the Beam container is built (next step).
# ===========================================================================

locals {
  create_job = var.template_spec_gcs_path != "" ? 1 : 0

  # Worker harness image = the same custom image as the launcher (Tesseract +
  # Presidio + embedding model). Without this, workers get the stock Beam image
  # and OCR fails at runtime. Single source: the Artifact Registry repo URL.
  sdk_image = "${var.image_repo_url}/${var.image_name}:${var.image_tag}"

  temp_location    = "gs://${var.staging_bucket}/temp"
  staging_location = "gs://${var.staging_bucket}/staging"
}

# ---------------------------------------------------------------------------
# Dataflow CMEK: the job encrypts launcher/worker VM disks and job state with
# the HSM KEK, so two Google-managed service agents must be able to USE the key:
#   - Compute Engine agent: encrypts the launcher + worker VM persistent disks.
#   - Dataflow agent:       encrypts Dataflow-managed job state.
# Without both, the launcher VM fails to start ("cloudkms ... useToEncrypt
# denied"). These agents already exist (their APIs are enabled), so a direct
# binding is safe.
# ---------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "compute_cmek" {
  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "dataflow_cmek" {
  crypto_key_id = var.kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@dataflow-service-producer-prod.iam.gserviceaccount.com"
}

resource "google_dataflow_flex_template_job" "scrubber" {
  count = local.create_job

  provider                = google-beta
  name                    = var.job_name
  project                 = var.project_id
  region                  = var.region
  container_spec_gcs_path  = var.template_spec_gcs_path

  # --- Confidential Computing (verified mechanism) ---
  additional_experiments = [
    "enable_confidential_compute",
  ]

  # N2D is mandatory for AMD SEV. n2d-standard-2 is the smallest N2D
  # (matches the low-cost target).
  machine_type = "n2d-standard-2"

  # --- Zero-Trust networking: no public IPs on workers ---
  ip_configuration = "WORKER_IP_PRIVATE"

  # --- Encryption at rest for Dataflow state/temp (CMEK, HSM-backed) ---
  kms_key_name = var.kms_key_id

  # --- Identity: dedicated least-privilege worker SA ---
  service_account_email = var.dataflow_worker_sa

  # --- Worker harness image (carries Tesseract/Presidio/embedding model) ---
  sdk_container_image = local.sdk_image

  # --- Staging (template graph) and temp (execution) on the CMEK bucket ---
  staging_location = local.staging_location
  temp_location    = local.temp_location

  # --- Keep worker count tiny for a POC; burst to a few for throughput ---
  max_workers = 3
  num_workers = 1

  # Streaming engine keeps worker disk small and cost down.
  enable_streaming_engine = true

  # Custom pipeline parameters consumed by the Beam code.
  parameters = {
    input_subscription = var.input_subscription
    cleaned_bucket     = var.cleaned_bucket

    # LanceDB dataset location (dataset written directly to CMEK GCS).
    lance_uri = "gs://${var.vectors_bucket}/lancedb/pii_store"

    # Field-level encryption: the worker encrypts SSN with the finance key
    # and address with the marketing key. It holds ENCRYPT on both, DECRYPT
    # on neither (enforced in the access_control module).
    finance_key_id   = var.finance_key_id
    marketing_key_id = var.marketing_key_id
  }

  labels = var.labels

  # Streaming jobs should drain (not cancel) so in-flight data isn't lost.
  on_delete = "drain"

  lifecycle {
    # CI republishes the spec on each container build; don't thrash the job.
    ignore_changes = [container_spec_gcs_path]
  }

  # The Compute/Dataflow agents must hold KEK access before the CMEK-encrypted
  # launcher VM is created, or the job fails to start.
  depends_on = [
    google_kms_crypto_key_iam_member.compute_cmek,
    google_kms_crypto_key_iam_member.dataflow_cmek,
  ]
}
