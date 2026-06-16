"""
Where envelope encryption sits inside the confidential Dataflow worker.

Pipeline (all inside AMD SEV worker memory):
  Pub/Sub msg (file landed)
    -> fetch file from GCS into /dev/shm (RAM disk; never hits worker disk)
    -> OCR if scan (Tesseract) / extract (PyMuPDF, python-docx, openpyxl)
    -> Presidio analyze -> entities (SSN, ADDRESS, NAME, ...)
    -> redact text for the embedding
    -> envelope-encrypt sensitive fields per department
    -> write row to LanceDB (CMEK GCS)

DEK lifecycle: the DepartmentEncryptor is created once per bundle (setup/
start_bundle), so its DEK is wrapped once and reused for every record in the
bundle. Output rows carry the (identical-within-bundle) wrapped DEK blob.
"""

import apache_beam as beam

from envelope_crypto import DepartmentEncryptor, gcp_master_aead


class EnvelopeEncryptFields(beam.DoFn):
    def __init__(self, finance_key_uri: str, marketing_key_uri: str):
        self._finance_key_uri = finance_key_uri
        self._marketing_key_uri = marketing_key_uri

    def start_bundle(self):
        # One DEK per department per bundle -> wrapped once, reused across the
        # bundle's records. This is the call-amortization that keeps us under
        # the non-raisable HSM KMS quota.
        self._fin = DepartmentEncryptor(gcp_master_aead(self._finance_key_uri))
        self._mkt = DepartmentEncryptor(gcp_master_aead(self._marketing_key_uri))

    def process(self, record):
        # `record` already has: record_id, redacted_text, embedding vector,
        # and the detected entities {ssn, address, ...} (all in SEV memory).
        rid = record["record_id"]
        ents = record["entities"]

        yield {
            "record_id": rid,
            "vector": record["vector"],
            "redacted_text": record["redacted_text"],
            # Locally AES-GCM encrypted; AAD-bound to (record_id, field).
            "encrypted_ssn": (
                self._fin.encrypt_field(ents["ssn"], rid, "ssn") if ents.get("ssn") else None
            ),
            "encrypted_address": (
                self._mkt.encrypt_field(ents["address"], rid, "address")
                if ents.get("address") else None
            ),
            # Wrapped DEKs so each department can later unwrap (if authorized).
            "wrapped_dek_finance": self._fin.wrapped_dek,
            "wrapped_dek_marketing": self._mkt.wrapped_dek,
        }


# LanceDB schema (written by the sink after this DoFn):
#   record_id:             string
#   vector:                fixed_size_list<float>   # from redacted_text
#   redacted_text:         string                    # admin-visible
#   encrypted_ssn:         binary                    # finance-only (AES-GCM)
#   encrypted_address:     binary                    # marketing-only (AES-GCM)
#   wrapped_dek_finance:   binary                    # unwrap needs finance KEK
#   wrapped_dek_marketing: binary                    # unwrap needs marketing KEK
