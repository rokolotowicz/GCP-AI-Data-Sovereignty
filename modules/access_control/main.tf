# ===========================================================================
# Field-Level Encryption access matrix.
#
# This module contains ZERO service-account or key creation. It only binds
# "who can do what to which key" — keeping the policy in one auditable place.
#
#   Identity            finance-key        marketing-key      LanceDB bucket
#   ----------------    ----------------   ----------------   --------------
#   dataflow-worker     ENCRYPT only       ENCRYPT only       read+write
#   consumer-finance    DECRYPT            (none)             read
#   consumer-marketing  (none)             DECRYPT            read
#   consumer-admin      (none)             (none)             read
#
# Result: the worker writes ciphertext for both domains but can read back
# neither. Each consumer can decrypt only its own domain. Admin can search
# vectors / read redacted text but every PII column stays opaque.
# ===========================================================================

# --- Worker: ENCRYPT on both field keys, DECRYPT on neither ---------------
resource "google_kms_crypto_key_iam_member" "worker_encrypt_finance" {
  crypto_key_id = var.finance_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:${var.dataflow_worker_sa}"
}

resource "google_kms_crypto_key_iam_member" "worker_encrypt_marketing" {
  crypto_key_id = var.marketing_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:${var.dataflow_worker_sa}"
}

# --- Finance: DECRYPT on finance key only ---------------------------------
resource "google_kms_crypto_key_iam_member" "finance_decrypt" {
  crypto_key_id = var.finance_key_id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${var.finance_sa}"
}

# --- Marketing: DECRYPT on marketing key only -----------------------------
resource "google_kms_crypto_key_iam_member" "marketing_decrypt" {
  crypto_key_id = var.marketing_key_id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${var.marketing_sa}"
}

# --- Admin: intentionally no key bindings. (Documented by absence.) -------

# --- Read access to the LanceDB dataset for all three consumers -----------
resource "google_storage_bucket_iam_member" "consumers_read" {
  for_each = toset([var.finance_sa, var.marketing_sa, var.admin_sa])
  bucket   = var.vectors_bucket
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${each.value}"
}

# ---------------------------------------------------------------------------
# KMS Data Access audit logging.
# REQUIRED for the "every SSN view is logged" claim — these logs are OFF by
# default. With this, each cryptoKeyVersions.decrypt call lands in Cloud
# Audit Logs (Data Access), tied to the calling identity.
# ---------------------------------------------------------------------------
resource "google_project_iam_audit_config" "kms" {
  project = var.project_id
  service = "cloudkms.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ" # decrypt / encrypt operations
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
