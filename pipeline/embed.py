"""
Embed redacted text locally with sentence-transformers.

Local on purpose: a managed embedding API would send text out of the VPC,
undercutting the data-residency/sovereignty story. all-MiniLM-L6-v2 is small
(~80MB) and outputs 384-dim vectors. The model is loaded once per worker.

Trade-off: pulls in torch, which materially increases the container image size.
Swap to a smaller/quantized model if image size or cold-start matters.
"""

from __future__ import annotations

from functools import lru_cache

_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
EMBED_DIM = 384


@lru_cache(maxsize=1)
def _model():
    from sentence_transformers import SentenceTransformer

    return SentenceTransformer(_MODEL_NAME)


def embed(text: str) -> list[float]:
    vec = _model().encode(text, normalize_embeddings=True)
    return vec.tolist()
