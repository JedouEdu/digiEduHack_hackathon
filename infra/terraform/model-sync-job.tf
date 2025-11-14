# Model Sync Job for Tabular Service
# This Cloud Run Job populates the shared model cache bucket with AI models

# Cloud Run Job for model synchronization
resource "google_cloud_run_v2_job" "model_sync" {
  name     = "tabular-model-sync"
  location = var.region
  project  = var.project_id

  template {
    template {
      service_account = google_service_account.model_sync_job.email
      
      # Mount the same shared volume as the service
      volumes {
        name = "models"
        gcs {
          bucket    = google_storage_bucket.tabular_model_cache.name
          read_only = false
        }
      }

      containers {
        # Reuse the same tabular service image
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}/${var.tabular_service_name}:latest"

        # Environment variables for sync mode
        env {
          name  = "MODEL_SYNC_MODE"
          value = "1"
        }

        env {
          name  = "MODEL_CACHE_PATH"
          value = "/models"
        }

        env {
          name  = "LLM_MODEL_NAME"
          value = var.tabular_llm_model_name
        }

        env {
          name  = "EMBEDDING_MODEL_NAME"
          value = var.tabular_embedding_model_name
        }

        env {
          name  = "OLLAMA_MODELS"
          value = "/models/ollama"
        }

        env {
          name  = "SENTENCE_TRANSFORMERS_HOME"
          value = "/models/sbert"
        }

        env {
          name  = "HUGGINGFACE_HUB_CACHE"
          value = "/models/sbert"
        }

        # Resource allocation (same as service for consistency)
        resources {
          limits = {
            cpu    = "2000m"
            memory = "4Gi"
          }
        }

        volume_mounts {
          name       = "models"
          mount_path = "/models"
        }
      }

      # Job timeout (15 minutes should be enough for model downloads)
      timeout = "900s"

      # Run to completion
      max_retries = 2
    }
  }

  depends_on = [
    google_storage_bucket.tabular_model_cache,
    google_service_account.model_sync_job
  ]
}

# Note: Cloud Scheduler removed - sync job is triggered manually only

