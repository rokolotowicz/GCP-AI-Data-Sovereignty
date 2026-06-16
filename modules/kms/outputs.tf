output "key_ring_id" {
  value = google_kms_key_ring.main.id
}

output "crypto_key_id" {
  description = "Fully qualified KEK resource ID"
  value       = google_kms_crypto_key.kek.id
}

output "field_key_finance_id" {
  description = "HSM key for finance-domain field encryption (e.g. SSN)"
  value       = google_kms_crypto_key.field_finance.id
}

output "field_key_marketing_id" {
  description = "HSM key for marketing-domain field encryption (e.g. address)"
  value       = google_kms_crypto_key.field_marketing.id
}
