#!/bin/bash
#
# Load pre-downloaded models into Ollama (offline)
# Copies model files from bundle into Ollama's model directory
#
# Usage: sudo ./load-models.sh <models_directory>
#

set -euo pipefail

MODELS_SOURCE_DIR="${1:-/tmp/deployment-bundle/models}"
OLLAMA_MODELS_DIR="/usr/share/ollama/.ollama/models"

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log_info "=== Loading Ollama Models (Offline) ==="

# Verify source directory exists
if [[ ! -d "$MODELS_SOURCE_DIR" ]]; then
    log_error "Models directory not found: $MODELS_SOURCE_DIR"
    exit 1
fi

# Count model files
MODEL_COUNT=$(find "$MODELS_SOURCE_DIR" -type f ! -name "manifest.txt" | wc -l)
if [[ $MODEL_COUNT -eq 0 ]]; then
    log_error "No model files found in $MODELS_SOURCE_DIR"
    exit 1
fi

log_info "Found $MODEL_COUNT model files to deploy"

# Display manifest if available
if [[ -f "$MODELS_SOURCE_DIR/manifest.txt" ]]; then
    log_info "Model manifest:"
    cat "$MODELS_SOURCE_DIR/manifest.txt"
fi

# Ensure Ollama models directory exists
log_info "Ensuring Ollama models directory exists: $OLLAMA_MODELS_DIR"
mkdir -p "$OLLAMA_MODELS_DIR"

# Stop Ollama service temporarily to prevent conflicts
if systemctl is-active --quiet ollama.service; then
    log_info "Stopping Ollama service temporarily"
    systemctl stop ollama.service
    NEED_RESTART=true
else
    NEED_RESTART=false
fi

# Copy models with progress
log_info "Copying models to $OLLAMA_MODELS_DIR"
rsync -av --progress "$MODELS_SOURCE_DIR/" "$OLLAMA_MODELS_DIR/" --exclude=manifest.txt

# Set ownership
log_info "Setting ownership to ollama:ollama"
chown -R ollama:ollama "$OLLAMA_MODELS_DIR"

# Set permissions
find "$OLLAMA_MODELS_DIR" -type d -exec chmod 755 {} \;
find "$OLLAMA_MODELS_DIR" -type f -exec chmod 644 {} \;

# Restart Ollama service
if [[ "$NEED_RESTART" == "true" ]]; then
    log_info "Restarting Ollama service"
    systemctl start ollama.service

    # Wait for service to be ready
    log_info "Waiting for Ollama to initialize..."
    sleep 5
fi

# Verify models are accessible
log_info "Verifying models are loaded..."
sleep 2

# Try to list models (may take a moment for Ollama to index them)
if command -v ollama &>/dev/null; then
    for i in {1..5}; do
        if ollama list &>/dev/null; then
            log_info "Available models:"
            ollama list
            break
        else
            log_info "Waiting for Ollama to index models... (attempt $i/5)"
            sleep 3
        fi
    done
else
    log_info "Note: Run 'ollama list' as the ollama user to verify models"
fi

log_info "✓ Model loading completed"

# Disk usage summary
log_info "Disk usage for models:"
du -sh "$OLLAMA_MODELS_DIR"

exit 0
