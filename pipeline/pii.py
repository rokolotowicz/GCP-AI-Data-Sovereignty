"""
PII detection and redaction with Microsoft Presidio.

Two outputs from one analysis pass:
  1. redacted_text  - all detected PII replaced with type tags, for embedding
                       and for the admin (zero-PII) view.
  2. sensitive       - the RAW values we will field-encrypt: {"ssn", "address"}.

Note on address detection: Presidio/spaCy emit LOCATION spans, which approximate
addresses but aren't a precise street-address recognizer. For production you'd
add a custom address recognizer / regex; this POC takes the first strong
LOCATION span as the address. Flagged honestly rather than overclaimed.
"""

from __future__ import annotations

from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import OperatorConfig

# Built once per worker (heavy: loads the spaCy model).
_analyzer = AnalyzerEngine()
_anonymizer = AnonymizerEngine()

# Entities we care about; SSN -> finance domain, LOCATION -> marketing domain.
_ENTITIES = ["US_SSN", "LOCATION", "PERSON", "PHONE_NUMBER", "EMAIL_ADDRESS", "CREDIT_CARD"]


def analyze_and_redact(text: str, language: str = "en") -> tuple[str, dict]:
    results = _analyzer.analyze(text=text, entities=_ENTITIES, language=language)

    # Replace every detected entity with a <TYPE> tag for the embedding view.
    redacted = _anonymizer.anonymize(
        text=text,
        analyzer_results=results,
        operators={"DEFAULT": OperatorConfig("replace", {"new_value": "<REDACTED>"})},
    ).text

    # Pull the raw values we will field-encrypt. Highest-score span per type.
    best: dict[str, tuple[float, str]] = {}
    for r in results:
        span = text[r.start:r.end]
        if r.entity_type not in best or r.score > best[r.entity_type][0]:
            best[r.entity_type] = (r.score, span)

    sensitive = {
        "ssn": best.get("US_SSN", (0, None))[1],
        "address": best.get("LOCATION", (0, None))[1],
    }
    return redacted, sensitive
