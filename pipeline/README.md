# Envelope Encryption (Tink DEK/KEK)

Field-level encryption for the confidential Dataflow pipeline. Moves from a
Cloud-API dependency (one KMS call per field) to a cryptographic-library
dependency (Google Tink), where KMS is touched only to wrap/unwrap the DEK.

## Files

- `envelope_crypto.py` — the crypto core (`DepartmentEncryptor` /
  `DepartmentDecryptor`). KMS is abstracted as a Tink `Aead` so the same code
  runs against real Cloud KMS in the worker and a local key in tests.
- `redaction_dofn.py` — the Beam `DoFn` showing where encryption sits and the
  LanceDB row shape (incl. `wrapped_dek_finance` / `wrapped_dek_marketing`).
- `test_envelope_crypto.py` — verifies round-trip, DEK reuse, AAD binding, and
  cross-department denial. Run: `python3 test_envelope_crypto.py`.

## The Three Scalability Pillars

1. **Latency.** Each field no longer triggers a KMS round-trip; KMS is called
   only to wrap the DEK (once per department per bundle) and to unwrap on read.
   A KMS call is tens of milliseconds — the win is removing one *per field*.
   Quote your measured per-record delta rather than a fixed number.

2. **Throughput.** The default Cloud KMS cryptographic-requests quota is
   ~60,000/min (1,000/sec), shared across the caller project. Critically, the
   **HSM** symmetric quota is a separate per-region cap that Google will **not**
   raise. Because our KEK is HSM-backed, per-field KMS calls would hit an
   immovable ceiling. Envelope encryption collapses N field operations into one
   wrap, so the verified test does 2,000 field encryptions in **2** KMS calls.

3. **Security (memory isolation).** The cleartext DEK exists only in the memory
   of the process holding it. On the write path that is the Dataflow worker
   inside AMD SEV — the DEK is never written to disk or sent over the wire in
   clear (only its KMS-wrapped form is persisted). On the read path the DEK is
   unwrapped into the consumer's process; in-use protection there holds only if
   that consumer also runs confidential — otherwise the read side is protected
   by per-key IAM + KMS audit logs, not by a TEE.

## How segregation survives envelope encryption

Storing the wrapped DEK on the row leaks nothing. To turn `wrapped_dek_finance`
back into a usable key you need `cloudkms.cryptoKeyDecrypter` on the finance
KEK. Marketing and admin can read the blob but KMS refuses to unwrap it for
them. The Terraform IAM matrix is therefore **unchanged** from the direct-
encryption design: worker = encrypter on both KEKs; each consumer = decrypter
on its own KEK; admin = neither. Only the in-pipeline mechanics changed.

## AAD binding

Every field is encrypted with AES-GCM associated data of `record_id|field_name`.
A ciphertext lifted into a different record or column fails to decrypt, so
encrypted values cannot be shuffled between rows or fields.

## Tink version

Tested against the `tink` Python package (top-level `tink.new_keyset_handle`,
`KeysetHandle.write(writer, master_aead)`, `tink.read_keyset_handle`). The GCP
KMS integration uses `tink.integration.gcpkms.GcpKmsClient`; install with
`pip install tink[gcpkms]` in the worker container.
