output "access_matrix" {
  description = "Human-readable summary of the FLE access matrix"
  value = {
    dataflow_worker = "encrypt: finance+marketing | decrypt: none"
    finance         = "decrypt: finance (SSN) | marketing: denied"
    marketing       = "decrypt: marketing (address) | finance: denied"
    admin           = "decrypt: none | search+redacted-text only"
  }
}
