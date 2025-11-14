#!/bin/bash
# Startup script for Tabular Service with shared model volume support
# This script handles Ollama startup, model caching, and FastAPI initialization

set -e

# Logging helpers
log_info() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [INFO] $*"
}

log_error() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [ERROR] $*" >&2
}

log_json() {
    local level="$1"
    local message="$2"
    shift 2
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"severity\":\"$level\",\"message\":\"$message\",$*}"
}

# Check if running in model sync mode
if [ "${MODEL_SYNC_MODE:-0}" = "1" ]; then
    log_info "Running in MODEL_SYNC_MODE - executing sync job"
    exec /app/scripts/model-sync-job.sh
    exit $?
fi

# Verify shared model volume availability if enabled
if [ "${SHARED_MODEL_VOLUME_ENABLED:-false}" = "true" ]; then
    log_info "Shared model volume enabled - verifying mount..."
    
    if [ ! -d "${MODEL_CACHE_PATH}" ]; then
        log_error "MODEL_CACHE_PATH ${MODEL_CACHE_PATH} does not exist"
        log_json "ERROR" "Shared volume mount missing" "\"model_cache_path\":\"${MODEL_CACHE_PATH}\",\"fatal\":true"
        exit 1
    fi
    
    # Check if mount is writable
    if ! touch "${MODEL_CACHE_PATH}/.write_test" 2>/dev/null; then
        log_error "MODEL_CACHE_PATH ${MODEL_CACHE_PATH} is not writable"
        log_json "ERROR" "Shared volume not writable" "\"model_cache_path\":\"${MODEL_CACHE_PATH}\",\"fatal\":true"
        exit 1
    fi
    rm -f "${MODEL_CACHE_PATH}/.write_test"
    
    log_info "Shared volume mount verified at ${MODEL_CACHE_PATH}"
    log_json "INFO" "Shared volume available" "\"model_cache_path\":\"${MODEL_CACHE_PATH}\",\"bucket\":\"tabular-model-cache\""
else
    log_info "Shared model volume disabled - using local storage"
    # Fallback to local paths
    export OLLAMA_MODELS="${HOME}/.ollama/models"
    export SENTENCE_TRANSFORMERS_HOME="${HOME}/.cache/torch/sentence_transformers"
    export HUGGINGFACE_HUB_CACHE="${HOME}/.cache/huggingface/hub"
fi

# Start Ollama service
log_info "Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
log_info "Waiting for Ollama to be ready..."
OLLAMA_READY=false
for i in {1..30}; do
    if curl -f http://localhost:11434/api/tags > /dev/null 2>&1; then
        log_info "Ollama is ready"
        OLLAMA_READY=true
        break
    fi
    sleep 1
done

if [ "$OLLAMA_READY" = "false" ]; then
    log_error "Ollama failed to start within 30 seconds"
    log_json "ERROR" "Ollama startup timeout" "\"ollama_pid\":${OLLAMA_PID},\"fatal\":true"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
fi

# Handle model loading with cache awareness
MANIFEST_PATH="${MODEL_CACHE_PATH}/manifest.json"
CACHE_HIT=false
SKIP_PULL=false

if [ "${SHARED_MODEL_VOLUME_ENABLED:-false}" = "true" ]; then
    log_info "Checking model manifest..."
    
    if [ -f "$MANIFEST_PATH" ] && [ -f "${MODEL_CACHE_PATH}/.done" ]; then
        log_info "Manifest found - checking model availability..."
        
        # Read manifest version
        if command -v jq >/dev/null 2>&1; then
            MANIFEST_VERSION=$(jq -r '.version // "unknown"' "$MANIFEST_PATH" 2>/dev/null || echo "unknown")
            OLLAMA_MODEL=$(jq -r '.models.ollama.name // "llama3.2:1b"' "$MANIFEST_PATH" 2>/dev/null || echo "llama3.2:1b")
        else
            MANIFEST_VERSION="unknown"
            OLLAMA_MODEL="${LLM_MODEL_NAME:-llama3.2:1b}"
        fi
        
        # Check if Ollama can list the model
        if ollama list | grep -q "${OLLAMA_MODEL%%:*}"; then
            log_info "Model cache hit - skipping download"
            log_json "INFO" "Model cache hit" "\"cache_hit\":true,\"manifest_version\":\"${MANIFEST_VERSION}\",\"model\":\"${OLLAMA_MODEL}\",\"source\":\"gcs\""
            CACHE_HIT=true
            SKIP_PULL=true
        else
            log_info "Model not found in cache - will download"
            log_json "INFO" "Model cache miss" "\"cache_hit\":false,\"cache_miss_reason\":\"model_not_found\",\"manifest_version\":\"${MANIFEST_VERSION}\""
        fi
    else
        log_info "Manifest not found - first run or sync pending"
        log_json "INFO" "Model cache miss" "\"cache_hit\":false,\"cache_miss_reason\":\"manifest_missing\""
    fi
fi

# Pull Ollama model if needed
if [ "$SKIP_PULL" = "false" ]; then
    MODEL_NAME="${LLM_MODEL_NAME:-llama3.2:1b}"
    log_info "Pulling Llama model: ${MODEL_NAME}..."
    
    if ollama pull "${MODEL_NAME}"; then
        log_info "Model ${MODEL_NAME} pulled successfully"
        log_json "INFO" "Model download complete" "\"model\":\"${MODEL_NAME}\",\"cache_hit\":false"
        
        # Update manifest if using shared volume
        if [ "${SHARED_MODEL_VOLUME_ENABLED:-false}" = "true" ] && command -v jq >/dev/null 2>&1; then
            log_info "Updating manifest after pull..."
            # Simple manifest update (sync job will do full update)
            cat > "${MANIFEST_PATH}.tmp" <<EOF
{
  "version": "$(date +%Y%m%d-%H%M%S)",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "models": {
    "ollama": {
      "name": "${MODEL_NAME}",
      "updated_by": "startup"
    }
  }
}
EOF
            mv "${MANIFEST_PATH}.tmp" "${MANIFEST_PATH}" 2>/dev/null || true
        fi
    else
        log_error "Failed to pull model ${MODEL_NAME} - service may have limited functionality"
        log_json "WARNING" "Model pull failed" "\"model\":\"${MODEL_NAME}\",\"retry_at_runtime\":true"
    fi
else
    log_info "Skipping model pull - using cached model"
fi

# Emit cache metrics
log_json "INFO" "Startup complete" "\"cache_hit\":${CACHE_HIT},\"shared_volume_enabled\":${SHARED_MODEL_VOLUME_ENABLED:-false},\"ollama_pid\":${OLLAMA_PID}"

# Start FastAPI application
log_info "Starting FastAPI application..."
exec uvicorn eduscale.main:app --host 0.0.0.0 --port "${PORT}"

