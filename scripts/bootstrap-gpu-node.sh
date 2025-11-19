#!/bin/bash
#
# Bootstrap script for air-gapped GPU node deployment
# Runs on the GPU node with NO internet access
#
# Usage: sudo ./bootstrap-gpu-node.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Verify we're offline (optional check)
check_offline() {
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        log_warn "Network connectivity detected - this should be an air-gapped node"
        log_warn "Proceeding anyway, but verify network isolation"
    else
        log_info "Confirmed: No internet connectivity (air-gapped)"
    fi
}

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_METADATA="$BASE_DIR/deployment.json"

log_info "=== Air-Gapped GPU Node Bootstrap ==="
log_info "Base directory: $BASE_DIR"

# Load deployment metadata
if [[ -f "$DEPLOYMENT_METADATA" ]]; then
    log_info "Deployment metadata:"
    cat "$DEPLOYMENT_METADATA"
else
    log_warn "No deployment metadata found"
fi

# Step 1: Verify bundle integrity
log_info "Step 1/5: Verifying bundle contents"
if [[ ! -d "$BASE_DIR/installers" ]] || [[ ! -d "$BASE_DIR/models" ]]; then
    log_error "Missing required directories in deployment bundle"
    exit 1
fi

if [[ ! -f "$BASE_DIR/installers/ollama" ]]; then
    log_error "Ollama binary not found in bundle"
    exit 1
fi

log_info "✓ Bundle verification passed"

# Step 2: Check offline status
log_info "Step 2/5: Checking network isolation"
check_offline

# Step 3: Install Ollama (offline)
log_info "Step 3/5: Installing Ollama"
cd "$SCRIPT_DIR"
chmod +x install-ollama-offline.sh
./install-ollama-offline.sh "$BASE_DIR/installers"

# Step 4: Load models
log_info "Step 4/5: Loading models"
chmod +x load-models.sh
./load-models.sh "$BASE_DIR/models"

# Step 5: Apply security hardening
log_info "Step 5/5: Applying security hardening"
chmod +x harden-node.sh
./harden-node.sh

# Final verification
log_info "=== Deployment Summary ==="
log_info "Ollama version: $(ollama --version 2>/dev/null || echo 'Not in PATH')"
log_info "Service status:"
systemctl status ollama --no-pager -l || log_warn "Service not running"

log_info ""
log_info "${GREEN}✓ Bootstrap completed successfully${NC}"
log_info ""
log_info "Next steps:"
log_info "  1. Verify models: ollama list"
log_info "  2. Test inference: ollama run codellama:7b 'def hello_world()'"
log_info "  3. Check logs: journalctl -u ollama -f"

exit 0
