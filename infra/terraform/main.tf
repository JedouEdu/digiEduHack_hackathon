# Enable Required Google Cloud APIs
resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_on_destroy = false
}

# Artifact Registry Repository for Docker Images
resource "google_artifact_registry_repository" "eduscale_repo" {
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for EduScale Engine container images"
  format        = "DOCKER"

  # Ensure API is enabled before creating repository
  depends_on = [google_project_service.artifact_registry]
}

# Cloud Run Service (v2)
resource "google_cloud_run_v2_service" "eduscale_engine" {
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    # Scaling configuration
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      # Container image from Artifact Registry
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}/${var.service_name}:${var.image_tag}"

      # Container port
      ports {
        container_port = var.container_port
      }

      # Resource limits
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Environment variables matching the FastAPI application
      env {
        name  = "ENV"
        value = var.environment
      }

      env {
        name  = "SERVICE_NAME"
        value = var.service_name
      }

      env {
        name  = "SERVICE_VERSION"
        value = var.service_version
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "GCP_REGION"
        value = var.region
      }

      env {
        name  = "GCP_RUN_SERVICE"
        value = var.service_name
      }
    }
  }

  # Ensure API is enabled and repository exists before creating service
  depends_on = [
    google_project_service.cloud_run,
    google_artifact_registry_repository.eduscale_repo
  ]
}

# IAM Policy to Allow Unauthenticated Access
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  location = google_cloud_run_v2_service.eduscale_engine.location
  name     = google_cloud_run_v2_service.eduscale_engine.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
