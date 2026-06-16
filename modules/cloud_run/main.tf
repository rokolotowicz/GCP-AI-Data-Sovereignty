# ---------------------------------------------------------------------------
# Cloud Run service running the Presidio redaction container.
# Note: Cloud Run does not support AMD SEV (Confidential Computing).
# For confidential-in-use guarantees, migrate this workload to Confidential
# Space on a Confidential VM after the POC is validated.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "main" {
  name     = var.service_name
  location = var.region
  project  = var.project_id

  # INGRESS_TRAFFIC_ALL is required so Eventarc (which routes via Pub/Sub
  # push) can reach the service. Authn is enforced via the run.invoker
  # role being granted ONLY to the Eventarc SA.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle = true
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "RAW_BUCKET"
        value = var.raw_bucket
      }
      env {
        name  = "CLEANED_BUCKET"
        value = var.cleaned_bucket
      }
      env {
        name  = "REGION"
        value = var.region
      }
    }

    timeout = "300s"
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [
      # The image is replaced by CI/CD after the Presidio container is built.
      # Allowing TF to overwrite would force a roll-back on every apply.
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# Eventarc trigger: GCS object finalize on the raw bucket -> Cloud Run
# ---------------------------------------------------------------------------
resource "google_eventarc_trigger" "gcs_finalize" {
  name     = "${var.service_name}-gcs-trigger"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = var.raw_bucket
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.main.name
      region  = var.region
    }
  }

  service_account = var.eventarc_sa
  labels          = var.labels
}
