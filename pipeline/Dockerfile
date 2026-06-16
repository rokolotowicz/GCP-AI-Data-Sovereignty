# ===========================================================================
# Single image used BOTH as the Flex Template launcher AND as the Dataflow
# worker (so workers have Tesseract + Presidio + the embedding model). The
# build script passes this same image as sdk_container_image, otherwise
# workers would get the stock Beam image with no OCR engine and fail at run.
#
# The launcher-base image derives from the Apache Beam Python SDK, so it
# carries the worker harness boot in addition to the template launcher.
# ===========================================================================
FROM gcr.io/dataflow-templates-base/python311-template-launcher-base:latest

ARG WORKDIR=/dataflow/template
WORKDIR ${WORKDIR}

# System dependency: the Tesseract OCR engine (pytesseract is just a wrapper).
# libgl1 is needed by some image stacks; tesseract-ocr-eng ships English data.
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-eng \
        libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Python deps (apache-beam already present in the base image).
COPY requirements.txt .
# Install the CPU-only torch FIRST, from the PyTorch CPU index. Workers are
# N2D CPU machines (no GPU), so the default CUDA torch wheel would drag ~2GB
# of unused nvidia-* / triton libraries. Pre-installing CPU torch means
# sentence-transformers finds it already satisfied and never pulls CUDA.
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir -r requirements.txt

# spaCy model used by Presidio's NER. Baked in so workers don't download at run.
RUN python -m spacy download en_core_web_lg

# Embedding model baked in so confidential workers need ZERO external (Hugging
# Face) egress at runtime. Cache into a fixed dir during build (Cloud Build has
# internet), then force offline so the worker never even attempts a call to
# huggingface.co - the private-IP worker couldn't reach it anyway.
ENV HF_HOME=/opt/hf-cache
ENV SENTENCE_TRANSFORMERS_HOME=/opt/hf-cache
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')"
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

# Pipeline source.
COPY *.py ${WORKDIR}/

# Flex Template launcher wiring.
# NOTE: we deliberately do NOT set FLEX_TEMPLATE_PYTHON_REQUIREMENTS_FILE.
# Every dependency is already installed in this image. Setting it makes the
# launcher run `pip download` against pypi.org at launch time, which fails on a
# private-IP (no-public-IP) worker because Private Google Access does not cover
# PyPI. The image is the single, self-contained source of dependencies.
ENV FLEX_TEMPLATE_PYTHON_PY_FILE="${WORKDIR}/main.py"
