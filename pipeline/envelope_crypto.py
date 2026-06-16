"""
Field-level envelope encryption for the Sovereign-AI pipeline, using Google Tink.

Model (DEK/KEK envelope):
  * A Data Encryption Key (DEK) is generated LOCALLY (AES-256-GCM via Tink).
  * The DEK is wrapped (encrypted) ONCE by a department's HSM-backed Cloud KMS
    key (the KEK) and the wrapped blob is stored on each row.
  * Fields are encrypted LOCALLY with the DEK -- no KMS round-trip per field.

Why this shape (and not Tink's KmsEnvelopeAead convenience primitive):
  KmsEnvelopeAead generates a fresh DEK and calls KMS on EVERY encrypt(), which
  reintroduces one KMS round-trip per field. Here we own the DEK so it can be
  reused across many fields/records in a bundle, wrapping it once. That reuse is
  the whole point -- it keeps us under the (non-raisable) HSM KMS quota.

Crypto-segregation:
  The wrapped DEK can only be unwrapped by an identity with cryptoKeyDecrypter on
  that department's KEK. Storing wrapped_dek_finance on the row leaks nothing:
  marketing/admin can read the blob but KMS refuses to unwrap it for them.

Confidential-computing boundary:
  The cleartext DEK exists only in the process that holds it. On the WRITE path
  that process is the Dataflow worker inside AMD SEV memory. On the READ path it
  is the consumer's query service -- in-use protection there requires that
  service to also be confidential; otherwise it is protected by IAM + audit only.

The KMS master key is abstracted as a Tink `Aead` ("master_aead"). In production
that is `GcpKmsClient(key_uri).get_aead(key_uri)`; in tests it is any local Aead.
"""

from __future__ import annotations

import io
from dataclasses import dataclass

import tink
from tink import aead
from tink import cleartext_keyset_handle


# Bind every field ciphertext to its (record_id, field_name) via AES-GCM
# associated data. This stops a ciphertext from being lifted from one
# record/field and replayed into another -- the decrypt will fail.
def _aad(record_id: str, field_name: str) -> bytes:
    return f"{record_id}|{field_name}".encode("utf-8")


def gcp_master_aead(key_uri: str, credentials_path: str = "") -> aead.Aead:
    """Production master AEAD: a handle to a Cloud KMS key.

    key_uri form:
      gcp-kms://projects/P/locations/L/keyRings/R/cryptoKeys/K
    Wrap  = one KMS encrypt; Unwrap = one KMS decrypt. Nothing else hits KMS.
    """
    from tink.integration import gcpkms

    aead.register()
    client = gcpkms.GcpKmsClient(key_uri, credentials_path)
    return client.get_aead(key_uri)


@dataclass
class WrappedDek:
    """A DEK wrapped by a department KEK, plus its in-memory primitive.

    Only `blob` is persisted (stored as wrapped_dek_<dept> on the row). The
    `aead` primitive stays in process memory and is never serialized in clear.
    """

    blob: bytes
    aead: aead.Aead


class DepartmentEncryptor:
    """Worker-side. Owns one DEK per department, wrapped once, reused for many
    fields. Call once per bundle/window per department, then encrypt freely."""

    def __init__(self, master_aead: aead.Aead):
        aead.register()
        self._master = master_aead
        self._dek = self._new_wrapped_dek()

    def _new_wrapped_dek(self) -> WrappedDek:
        # Generate a fresh local DEK (AES-256-GCM).
        dek_handle = tink.new_keyset_handle(aead.aead_key_templates.AES256_GCM)
        # Wrap it ONCE with a single KMS *encrypt*.
        #
        # We deliberately do NOT use dek_handle.write(writer, self._master):
        # Tink's encrypted-keyset write VERIFIES the wrap by decrypting it again
        # before returning, which would force this worker identity to hold
        # cryptoKeyDecrypter on the KEK -- breaking the encrypt-only model (the
        # worker must seal data it can never read back). Instead we serialize
        # the DEK keyset in cleartext *in memory only* (it never leaves this
        # SEV-protected process) and wrap those bytes with one encrypt call.
        # Unwrap is one master_aead.decrypt() on the reader side, gated by
        # cryptoKeyDecrypter -- which only the department consumer holds.
        buf = io.BytesIO()
        cleartext_keyset_handle.write(tink.BinaryKeysetWriter(buf), dek_handle)
        wrapped = self._master.encrypt(buf.getvalue(), b"")  # single KMS encrypt
        return WrappedDek(blob=wrapped, aead=dek_handle.primitive(aead.Aead))

    @property
    def wrapped_dek(self) -> bytes:
        """The blob to store on each row for this department."""
        return self._dek.blob

    def encrypt_field(self, plaintext: str, record_id: str, field_name: str) -> bytes:
        return self._dek.aead.encrypt(plaintext.encode("utf-8"), _aad(record_id, field_name))


class DepartmentDecryptor:
    """Reader-side. Unwraps a stored DEK ONCE via KMS, then decrypts locally."""

    def __init__(self, master_aead: aead.Aead, wrapped_dek_blob: bytes):
        aead.register()
        # One KMS *decrypt* to unwrap; fails here if the identity lacks
        # cryptoKeyDecrypter on this department's KEK. Mirrors the wrap side:
        # master_aead.decrypt() -> cleartext DEK keyset bytes -> handle.
        serialized_dek = master_aead.decrypt(wrapped_dek_blob, b"")
        dek_handle = cleartext_keyset_handle.read(
            tink.BinaryKeysetReader(serialized_dek)
        )
        self._dek_aead = dek_handle.primitive(aead.Aead)

    def decrypt_field(self, ciphertext: bytes, record_id: str, field_name: str) -> str:
        return self._dek_aead.decrypt(ciphertext, _aad(record_id, field_name)).decode("utf-8")
