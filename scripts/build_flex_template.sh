#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the confidential PII-scrubber container and publish the Flex Template
# spec. Run from the repo root:  ./scripts/build_flex_template.sh
#
# After it prints the spec path, set in terraform.tfvars:
#   dataflow_template_spec = "gs://<PROJECT>-dataflow/templates/pii-scrubber.json"
# and re-apply so the confidential Dataflow job launches.
# ---------------------------------------------------------------------------
set -euo pipefail

PROJECT="${PROJECT:-sovereign-ai-499423}"
REGION="${REGION:-us-central1}"
REPO="${REPO:-sovereign-ai}"
TAG="${TAG:-v1}"

IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/pii-scrubber:${TAG}"
STAGING_BUCKET="gs://${PROJECT}-dataflow"
SPEC_PATH="${STAGING_BUCKET}/templates/pii-scrubber.json"

echo ">> Building + pushing image via Cloud Build:"
echo "   ${IMAGE}"
# Build context is ./pipeline (Dockerfile + source + requirements live there).
gcloud builds submit ./pipeline \
  --tag "${IMAGE}" \
  --project "${PROJECT}"

echo ">> Publishing Flex Template spec:"
echo "   ${SPEC_PATH}"
gcloud dataflow flex-template build "${SPEC_PATH}" \
  --image "${IMAGE}" \
  --sdk-language "PYTHON" \
  --metadata-file ./pipeline/metadata.json \
  --project "${PROJECT}"

cat <<EOF

Done.

The same image is the launcher AND the worker. When the Terraform job launches,
it must run workers on this image (so they have Tesseract/Presidio). Pass it as
a pipeline option:  sdk_container_image=${IMAGE}

Next:
  1) Ensure a staging bucket exists: ${STAGING_BUCKET}
  2) Set in terraform.tfvars:
       dataflow_template_spec = "${SPEC_PATH}"
  3) Re-apply Terraform to launch the confidential streaming job.
EOF
