resource "google_kms_key_ring" "main" {
  name     = "sovereign-ai-keyring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "kek" {
  name            = "sovereign-ai-kek"
  key_ring        = google_kms_key_ring.main.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days
  labels          = var.labels

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  lifecycle {
    prevent_destroy = false # set to true before going to prod
  }
}

# ---------------------------------------------------------------------------
# Field-level encryption keys (one per department / need-to-know domain).
# These are SEPARATE from the KEK above (which is for CMEK-at-rest).
# Crypto-segregation is enforced by who holds decrypt on each key, set in
# the access_control module — NOT here.
# ---------------------------------------------------------------------------
resource "google_kms_crypto_key" "field_finance" {
  name            = "pii-field-finance"
  key_ring        = google_kms_key_ring.main.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days
  labels          = merge(var.labels, { fle-domain = "finance" })

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }
}

resource "google_kms_crypto_key" "field_marketing" {
  name            = "pii-field-marketing"
  key_ring        = google_kms_key_ring.main.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days
  labels          = merge(var.labels, { fle-domain = "marketing" })

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }
}
