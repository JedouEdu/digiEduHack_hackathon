# Cloud Run Service for MIME Decoder
# This service receives Cloud Storage events from Eventarc, detects file types,
# and routes files to the appropriate Transformer service for processing.
resource "google_cloud_run_service" "mime_decoder" {
  name     = var.mime_decoder_service_name
  location = var.region
  project  = var.project_id

  template {
    spec {
      containers {
        # Image will be updated via CI/CD
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}/${var.mime_decoder_service_name}:${var.image_tag}"

        # Environment variables
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "GCP_REGION"
          value = var.region
        }

        env {
          name  = "UPLOADS_BUCKET"
          value = google_storage_bucket.uploads.name
        }

        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        # Resource limits
        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        # Container port
        ports {
          container_port = var.container_port
        }
      }

      # Service account for accessing Cloud Storage
      service_account_name = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"

      # Auto-scaling configuration
      container_concurrency = 80
      timeout_seconds       = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = tostring(var.min_instance_count)
        "autoscaling.knative.dev/maxScale" = tostring(var.max_instance_count)
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  # Ensure API and repository are ready before creating service
  depends_on = [
    google_project_service.cloud_run,
    google_artifact_registry_repository.jedouscale_repo
  ]

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }
}

# Grant Eventarc service account permission to invoke MIME Decoder
resource "google_cloud_run_service_iam_member" "eventarc_invoker" {
  service  = google_cloud_run_service.mime_decoder.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.eventarc_trigger.email}"
  project  = var.project_id
}

# Allow unauthenticated access to MIME Decoder if configured
# Note: In production, this should be false and only Eventarc should invoke the service
resource "google_cloud_run_service_iam_member" "mime_decoder_public_access" {
  count    = var.allow_unauthenticated ? 1 : 0
  service  = google_cloud_run_service.mime_decoder.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_id
}

# Eventarc Trigger for Cloud Storage OBJECT_FINALIZE events
# Automatically triggers MIME Decoder when files are uploaded to the bucket
resource "google_eventarc_trigger" "storage_trigger" {
  name     = var.eventarc_trigger_name
  location = var.region
  project  = var.project_id

  # Subscribe to Cloud Storage OBJECT_FINALIZE events
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  # Filter events by bucket name
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.uploads.name
  }

  # Optional: Filter events by object name prefix
  # Only applied if event_filter_prefix is not empty
  dynamic "matching_criteria" {
    for_each = var.event_filter_prefix != "" ? [1] : []
    content {
      attribute = "bucket"
      value     = google_storage_bucket.uploads.name
      operator  = "match-path-pattern"
    }
  }

  # Route events to MIME Decoder Cloud Run service
  destination {
    cloud_run_service {
      service = google_cloud_run_service.mime_decoder.name
      region  = var.region
    }
  }

  # Retry policy for failed event deliveries
  # Eventarc automatically retries failed deliveries with exponential backoff
  # Default behavior: 5 retries with intervals: 10s, 20s, 40s, 80s, 160s
  # For Cloud Run destinations, retries occur when:
  # - Service returns 5xx status codes
  # - Service times out (timeout_seconds in Cloud Run service)
  # - Service is unavailable
  # Note: 4xx errors are NOT retried as they indicate client errors

  # Use Eventarc service account for invoking Cloud Run
  service_account = google_service_account.eventarc_trigger.email

  # Ensure all dependencies are ready
  depends_on = [
    google_project_service.eventarc,
    google_cloud_run_service.mime_decoder,
    google_cloud_run_service_iam_member.eventarc_invoker,
    google_storage_bucket.uploads
  ]
}
