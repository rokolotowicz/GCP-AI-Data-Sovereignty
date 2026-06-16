"""
Sovereign-AI confidential streaming pipeline (Flex Template entrypoint).

Flow (all inside AMD SEV worker memory):
  Pub/Sub (GCS object-finalized notification)
    -> parse bucket/object
    -> fetch bytes to /dev/shm, extract text (OCR if scanned)
    -> Presidio analyze + redact
    -> embed redacted text (local model)
    -> envelope-encrypt SSN (finance KEK) + address (marketing KEK)
    -> write {vector, redacted_text, ciphertexts, wrapped DEKs} to LanceDB

The job is streaming and long-lived; it is launched from the Flex Template
spec produced by scripts/build_flex_template.sh.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import uuid

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from extract import extract_text
from pii import analyze_and_redact
from embed import embed
from redaction_dofn import EnvelopeEncryptFields
from lance_sink import WriteToLanceDB

# RAM disk so extracted plaintext never lands on persistent worker disk.
_SHM = "/dev/shm"


class ParseNotification(beam.DoFn):
    """GCS object-finalized notification (JSON_API_V1) -> {bucket, name}."""

    def process(self, message_bytes):
        attrs = json.loads(message_bytes.decode("utf-8"))
        name = attrs.get("name")
        bucket = attrs.get("bucket")
        if name and bucket:
            yield {"bucket": bucket, "name": name}


class FetchAndExtract(beam.DoFn):
    def setup(self):
        from google.cloud import storage

        self._gcs = storage.Client()

    def process(self, ref):
        blob = self._gcs.bucket(ref["bucket"]).blob(ref["name"])
        data = blob.download_as_bytes()

        # Stage to tmpfs only if a path-based tool needs it; extract_text works
        # on bytes directly, so we keep it in memory. (tmpfs path available at
        # _SHM if a future extractor needs a real file.)
        text = extract_text(data, ref["name"], blob.content_type or "")

        yield {
            "record_id": f"{ref['name']}::{uuid.uuid4().hex[:8]}",
            "source": ref["name"],
            "text": text,
        }


class AnalyzeRedact(beam.DoFn):
    def process(self, rec):
        redacted, sensitive = analyze_and_redact(rec["text"])
        rec["redacted_text"] = redacted
        rec["entities"] = sensitive  # {"ssn": ..., "address": ...}
        del rec["text"]              # drop raw text ASAP
        yield rec


class Embed(beam.DoFn):
    def process(self, rec):
        rec["vector"] = embed(rec["redacted_text"])
        yield rec


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_subscription", required=True)
    parser.add_argument("--lance_uri", required=True)
    parser.add_argument("--finance_key_id", required=True)    # gcp-kms://... or KMS resource id
    parser.add_argument("--marketing_key_id", required=True)
    parser.add_argument("--cleaned_bucket", required=False)
    known, beam_args = parser.parse_known_args(argv)

    opts = PipelineOptions(beam_args, streaming=True, save_main_session=True)
    opts.view_as(StandardOptions).streaming = True

    fin_uri = _as_tink_uri(known.finance_key_id)
    mkt_uri = _as_tink_uri(known.marketing_key_id)

    with beam.Pipeline(options=opts) as p:
        (
            p
            | "ReadPubSub" >> beam.io.ReadFromPubSub(subscription=known.input_subscription)
            | "Parse" >> beam.ParDo(ParseNotification())
            | "FetchExtract" >> beam.ParDo(FetchAndExtract())
            | "AnalyzeRedact" >> beam.ParDo(AnalyzeRedact())
            | "Embed" >> beam.ParDo(Embed())
            | "EnvelopeEncrypt" >> beam.ParDo(EnvelopeEncryptFields(fin_uri, mkt_uri))
            | "WriteLanceDB" >> beam.ParDo(WriteToLanceDB(known.lance_uri))
        )


def _as_tink_uri(key_id: str) -> str:
    """Tink's GCP KMS client expects a gcp-kms:// URI.

    Accepts either a bare KMS resource id
    (projects/.../cryptoKeys/...) or an already-prefixed gcp-kms:// URI.
    """
    if key_id.startswith("gcp-kms://"):
        return key_id
    return "gcp-kms://" + key_id


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
