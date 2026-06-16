project_id      = "sovereign-ai-499423"
project_number  = "142959187197"
region          = "us-central1"
env             = "poc"
bucket_prefix   = "sovereign-ai-499423"

# Leave as the placeholder until the Presidio image is built and pushed.
# After pushing, update to e.g.:
# cloud_run_image = "us-central1-docker.pkg.dev/sovereign-ai-499423/sovereign-ai/presidio-redactor:v1"
cloud_run_image = "us-docker.pkg.dev/cloudrun/container/hello"

# Leave empty for the first apply (stands up Pub/Sub, buckets, SAs, KMS, AR).
# After building + publishing the Beam Flex Template, set this and re-apply
# to launch the confidential streaming job:
# dataflow_template_spec = "gs://sovereign-ai-499423-dataflow/templates/pii-scrubber.json"
dataflow_template_spec = "gs://sovereign-ai-499423-dataflow/templates/pii-scrubber.json"