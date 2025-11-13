# Cloud Run Service URL
output "cloud_run_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.eduscale_engine.uri
}

# Artifact Registry Repository URL
output "artifact_registry_repository" {
  description = "The full Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}

# Full Image Path
output "full_image_path" {
  description = "The complete image path used by Cloud Run"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}/${var.service_name}:${var.image_tag}"
}

# Project ID (for confirmation)
output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

# Region (for confirmation)
output "region" {
  description = "The GCP region"
  value       = var.region
}

# Service Name (for confirmation)
output "service_name" {
  description = "The Cloud Run service name"
  value       = var.service_name
}
