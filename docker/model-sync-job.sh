#!/bin/bash
# Model Sync Job for Tabular Service
# Downloads AI models into shared GCS volume and creates manifest

set -e

# Configuration
MODEL_CACHE_PATH="${MODEL_CACHE_PATH:-/models}"
OLLAMA_MODEL="${LLM_MODEL_NAME:-llama3.2:1b}"
EMBEDDING_MODEL="${EMBEDDING_MODEL_NAME:-BAAI/bge-m3}"
VERSION=$(date +%Y%m%d-%H%M%S)
TMP_DIR="${MODEL_CACHE_PATH}/.tmp/${VERSION}"

# Logging helpers
log_info() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [SYNC] [INFO] $*"
}

log_error() {
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [SYNC] [ERROR] $*" >&2
}

log_json() {
    local level="$1"
    local message="$2"
    shift 2
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"severity\":\"$level\",\"message\":\"$message\",\"job\":\"model-sync\",$*}"
}

# Verify mount availability
if [ ! -d "${MODEL_CACHE_PATH}" ]; then
    log_error "MODEL_CACHE_PATH ${MODEL_CACHE_PATH} does not exist"
    log_json "ERROR" "Mount missing" "\"model_cache_path\":\"${MODEL_CACHE_PATH}\",\"fatal\":true"
    exit 1
fi

if ! touch "${MODEL_CACHE_PATH}/.write_test" 2>/dev/null; then
    log_error "MODEL_CACHE_PATH ${MODEL_CACHE_PATH} is not writable"
    log_json "ERROR" "Mount not writable" "\"model_cache_path\":\"${MODEL_CACHE_PATH}\",\"fatal\":true"
    exit 1
fi
rm -f "${MODEL_CACHE_PATH}/.write_test"

log_info "Starting model sync job version ${VERSION}"
log_json "INFO" "Sync job started" "\"version\":\"${VERSION}\",\"model_cache_path\":\"${MODEL_CACHE_PATH}\""

# Create temporary directory
mkdir -p "${TMP_DIR}"
log_info "Created temporary directory: ${TMP_DIR}"

# Start Ollama for model downloads
log_info "Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
log_info "Waiting for Ollama to be ready..."
for i in {1..30}; do
    if curl -f http://localhost:11434/api/tags > /dev/null 2>&1; then
        log_info "Ollama is ready"
        break
    fi
    sleep 1
done

# Download Ollama model
log_info "Downloading Ollama model: ${OLLAMA_MODEL}..."
log_json "INFO" "Downloading Ollama model" "\"model\":\"${OLLAMA_MODEL}\",\"version\":\"${VERSION}\""

if ollama pull "${OLLAMA_MODEL}"; then
    log_info "Ollama model ${OLLAMA_MODEL} downloaded successfully"
    log_json "INFO" "Ollama model downloaded" "\"model\":\"${OLLAMA_MODEL}\",\"success\":true"
else
    log_error "Failed to download Ollama model ${OLLAMA_MODEL}"
    log_json "ERROR" "Ollama model download failed" "\"model\":\"${OLLAMA_MODEL}\",\"fatal\":true"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
fi

# Get model info and checksum
OLLAMA_CHECKSUM=""
if ollama list | grep -q "${OLLAMA_MODEL%%:*}"; then
    # Get model digest/hash if available
    OLLAMA_CHECKSUM=$(ollama list | grep "${OLLAMA_MODEL%%:*}" | awk '{print $3}' || echo "unknown")
fi

log_info "Ollama model checksum: ${OLLAMA_CHECKSUM}"

# Download sentence-transformers model using Python
log_info "Downloading sentence-transformers model: ${EMBEDDING_MODEL}..."
log_json "INFO" "Downloading embedding model" "\"model\":\"${EMBEDDING_MODEL}\",\"version\":\"${VERSION}\""

# Set temp cache for sentence-transformers
export SENTENCE_TRANSFORMERS_HOME="${TMP_DIR}/sbert"
export HUGGINGFACE_HUB_CACHE="${TMP_DIR}/sbert"
mkdir -p "${SENTENCE_TRANSFORMERS_HOME}"

# Download the model using Python (download only, don't load into memory to avoid OOM)
if python3 -c "
from huggingface_hub import snapshot_download
import sys
import os
try:
    cache_dir = '${TMP_DIR}/sbert'
    model_name = '${EMBEDDING_MODEL}'.replace('/', '--')
    snapshot_download(
        repo_id='${EMBEDDING_MODEL}',
        cache_dir=cache_dir,
        local_dir=os.path.join(cache_dir, f'models--{model_name}'),
        local_dir_use_symlinks=False
    )
    print('Model downloaded successfully')
    sys.exit(0)
except Exception as e:
    print(f'Error downloading model: {e}', file=sys.stderr)
    sys.exit(1)
"; then
    log_info "Embedding model ${EMBEDDING_MODEL} downloaded successfully"
    log_json "INFO" "Embedding model downloaded" "\"model\":\"${EMBEDDING_MODEL}\",\"success\":true"
else
    log_error "Failed to download embedding model ${EMBEDDING_MODEL}"
    log_json "ERROR" "Embedding model download failed" "\"model\":\"${EMBEDDING_MODEL}\",\"fatal\":true"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
fi

# Generate checksums for embedding model
EMBEDDING_CHECKSUM=$(find "${TMP_DIR}/sbert" -type f -name "*.bin" -o -name "*.safetensors" | head -n1 | xargs sha256sum 2>/dev/null | awk '{print $1}' || echo "unknown")
log_info "Embedding model checksum: ${EMBEDDING_CHECKSUM}"

# Create manifest
MANIFEST_PATH="${TMP_DIR}/manifest.json"
log_info "Creating manifest at ${MANIFEST_PATH}..."

cat > "${MANIFEST_PATH}" <<EOF
{
  "version": "${VERSION}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "models": {
    "ollama": {
      "name": "${OLLAMA_MODEL}",
      "checksum": "${OLLAMA_CHECKSUM}",
      "path": "${MODEL_CACHE_PATH}/ollama"
    },
    "embedding": {
      "name": "${EMBEDDING_MODEL}",
      "checksum": "${EMBEDDING_CHECKSUM}",
      "path": "${MODEL_CACHE_PATH}/sbert"
    }
  },
  "sync_job": {
    "version": "${VERSION}",
    "status": "completed",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
}
EOF

log_info "Manifest created successfully"
log_json "INFO" "Manifest created" "\"manifest_version\":\"${VERSION}\",\"path\":\"${MANIFEST_PATH}\""

# Atomically promote models from tmp to production
log_info "Promoting models to production..."

# Copy Ollama models (already in OLLAMA_MODELS location)
if [ -d "${HOME}/.ollama/models" ]; then
    log_info "Copying Ollama models to ${MODEL_CACHE_PATH}/ollama"
    mkdir -p "${MODEL_CACHE_PATH}/ollama"
    cp -r "${HOME}/.ollama/models/"* "${MODEL_CACHE_PATH}/ollama/" 2>/dev/null || true
fi

# Move sentence-transformers cache
if [ -d "${TMP_DIR}/sbert" ]; then
    log_info "Moving sentence-transformers cache to ${MODEL_CACHE_PATH}/sbert"
    rm -rf "${MODEL_CACHE_PATH}/sbert"
    mv "${TMP_DIR}/sbert" "${MODEL_CACHE_PATH}/sbert"
fi

# Move manifest
log_info "Moving manifest to ${MODEL_CACHE_PATH}/manifest.json"
mv "${MANIFEST_PATH}" "${MODEL_CACHE_PATH}/manifest.json"

# Create .done marker
touch "${MODEL_CACHE_PATH}/.done"
echo "${VERSION}" > "${MODEL_CACHE_PATH}/.done"

log_info "Models promoted successfully"
log_json "INFO" "Models promoted" "\"version\":\"${VERSION}\",\"ollama_path\":\"${MODEL_CACHE_PATH}/ollama\",\"sbert_path\":\"${MODEL_CACHE_PATH}/sbert\""

# Cleanup old versions (keep last 3)
log_info "Cleaning up old temporary directories..."
OLD_DIRS=$(find "${MODEL_CACHE_PATH}/.tmp" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | tail -n +4)
if [ -n "$OLD_DIRS" ]; then
    echo "$OLD_DIRS" | xargs rm -rf
    log_info "Removed old temporary directories"
    log_json "INFO" "Cleanup completed" "\"removed_dirs\":$(echo "$OLD_DIRS" | wc -l)"
fi

# Cleanup .tmp directories older than 7 days
find "${MODEL_CACHE_PATH}/.tmp" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

# Stop Ollama
kill $OLLAMA_PID 2>/dev/null || true

log_info "Model sync job completed successfully"
log_json "INFO" "Sync job completed" "\"version\":\"${VERSION}\",\"success\":true,\"manifest_path\":\"${MODEL_CACHE_PATH}/manifest.json\""

exit 0

