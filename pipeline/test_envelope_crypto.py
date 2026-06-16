"""
Validates the envelope encryption logic WITHOUT real GCP KMS by substituting a
local Tink AEAD for each department's KMS master key. Same code path the worker
uses; only the master AEAD differs.

Proves:
  1. Round-trip: encrypt with DEK -> wrap -> store blob -> unwrap -> decrypt.
  2. DEK reuse: many fields, one wrap (the throughput claim).
  3. AAD binding: a ciphertext can't be moved to another field/record.
  4. Crypto-segregation: marketing's KEK cannot unwrap finance's wrapped DEK.
"""

import tink
from tink import aead

from envelope_crypto import DepartmentEncryptor, DepartmentDecryptor


def local_kek() -> aead.Aead:
    aead.register()
    return tink.new_keyset_handle(aead.aead_key_templates.AES256_GCM).primitive(aead.Aead)


def main() -> None:
    aead.register()
    finance_kek = local_kek()    # stands in for pii-field-finance HSM key
    marketing_kek = local_kek()  # stands in for pii-field-marketing HSM key

    # --- WORKER (inside SEV): one DEK per department, wrapped once ---
    fin_enc = DepartmentEncryptor(finance_kek)
    mkt_enc = DepartmentEncryptor(marketing_kek)

    rows = []
    for i in range(1000):  # 1000 records, many fields each...
        rid = f"rec-{i}"
        rows.append({
            "record_id": rid,
            "redacted_text": "User [REDACTED] from [REDACTED]",
            "encrypted_ssn": fin_enc.encrypt_field("123-45-6789", rid, "ssn"),
            "encrypted_address": mkt_enc.encrypt_field("1 Main St", rid, "address"),
            "wrapped_dek_finance": fin_enc.wrapped_dek,
            "wrapped_dek_marketing": mkt_enc.wrapped_dek,
        })

    # 2. DEK reuse: the wrapped blob is identical across all rows -> wrapped once.
    assert len({r["wrapped_dek_finance"] for r in rows}) == 1, "DEK should be reused"
    print("[2] DEK reuse: 1000 records, 2000 field encryptions, 2 KMS wrap calls. OK")

    r = rows[0]

    # 1. Finance reads SSN.
    fin_view = DepartmentDecryptor(finance_kek, r["wrapped_dek_finance"])
    assert fin_view.decrypt_field(r["encrypted_ssn"], r["record_id"], "ssn") == "123-45-6789"
    print("[1] Round-trip: finance decrypted SSN. OK")

    # Marketing reads address.
    mkt_view = DepartmentDecryptor(marketing_kek, r["wrapped_dek_marketing"])
    assert mkt_view.decrypt_field(r["encrypted_address"], r["record_id"], "address") == "1 Main St"
    print("    Round-trip: marketing decrypted address. OK")

    # 3. AAD binding: lifting finance's SSN ciphertext into a different field fails.
    try:
        fin_view.decrypt_field(r["encrypted_ssn"], r["record_id"], "address")
        raise SystemExit("FAIL: AAD mismatch should have raised")
    except tink.TinkError:
        print("[3] AAD binding: ciphertext rejected under wrong field context. OK")

    # 4. Segregation: marketing's KEK cannot unwrap finance's wrapped DEK.
    try:
        DepartmentDecryptor(marketing_kek, r["wrapped_dek_finance"])
        raise SystemExit("FAIL: marketing should not unwrap finance DEK")
    except tink.TinkError:
        print("[4] Segregation: marketing KEK refused finance wrapped DEK. OK")

    print("\nALL CHECKS PASSED")


if __name__ == "__main__":
    main()
