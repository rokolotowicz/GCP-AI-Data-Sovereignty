"""
LanceDB sink. Writes rows to a Lance table backed by CMEK-encrypted GCS
(gs://...), so the vector store inherits the HSM-backed key at rest.

Concurrency note: Lance tables use optimistic-concurrency commits. Many Beam
workers appending to the same table can conflict and retry. For this POC we
batch within each bundle and append; keep worker parallelism modest. For higher
throughput, shard by table or funnel writes through a single sink stage.

Auth: relies on the worker SA's Application Default Credentials. If the object
store can't resolve creds, pass storage_options={"service_account": "..."} to
lancedb.connect (see Lance object-store docs).
"""

from __future__ import annotations

import apache_beam as beam
import pyarrow as pa

from embed import EMBED_DIM

_TABLE = "pii_store"

_SCHEMA = pa.schema([
    ("record_id", pa.string()),
    ("vector", pa.list_(pa.float32(), EMBED_DIM)),
    ("redacted_text", pa.string()),
    ("encrypted_ssn", pa.binary()),
    ("encrypted_address", pa.binary()),
    ("wrapped_dek_finance", pa.binary()),
    ("wrapped_dek_marketing", pa.binary()),
])


class WriteToLanceDB(beam.DoFn):
    def __init__(self, lance_uri: str):
        self._uri = lance_uri  # gs://<vectors-bucket>/lancedb/pii_store
        self._buf: list[dict] = []

    def setup(self):
        import lancedb

        self._db = lancedb.connect(self._uri)
        try:
            self._table = self._db.open_table(_TABLE)
        except Exception:
            self._table = self._db.create_table(_TABLE, schema=_SCHEMA)

    def process(self, row):
        self._buf.append(row)
        if len(self._buf) >= 200:
            self._flush()

    def finish_bundle(self):
        self._flush()

    def _flush(self):
        if not self._buf:
            return
        self._table.add(pa.Table.from_pylist(self._buf, schema=_SCHEMA))
        self._buf = []
