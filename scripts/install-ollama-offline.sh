#!/bin/bash
#
# Offline Ollama installation script for RHEL/Rocky/AlmaLinux
# NO internet access required - all artifacts provided locally
#
# Usage: sudo ./install-ollama-offline.sh <installer_directory>
#

set -euo pipefail

INSTALLER_DIR="${1:-/tmp/deployment-bundle/installers}"
OLLAMA_BINARY="$INSTALLER_DIR/ollama"

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

log_info "=== Offline Ollama Installation ==="

# Verify binary exists
if [[ ! -f "$OLLAMA_BINARY" ]]; then
    log_error "Ollama binary not found at: $OLLAMA_BINARY"
    exit 1
fi

# Verify binary is executable
if [[ ! -x "$OLLAMA_BINARY" ]]; then
    chmod +x "$OLLAMA_BINARY"
fi

# Create ollama user and group if they don't exist
if ! id -u ollama &>/dev/null; then
    log_info "Creating ollama user"
    useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
else
    log_info "User 'ollama' already exists"
fi

# Install binary
log_info "Installing Ollama binary to /usr/local/bin/ollama"
install -o root -g root -m 755 "$OLLAMA_BINARY" /usr/local/bin/ollama

# Verify installation
if ! /usr/local/bin/ollama --version &>/dev/null; then
    log_error "Ollama binary installation failed"
    exit 1
fi

OLLAMA_VERSION=$(/usr/local/bin/ollama --version)
log_info "Installed: $OLLAMA_VERSION"

# Create Ollama data directories
log_info "Creating Ollama data directories"
mkdir -p /usr/share/ollama/.ollama/models
chown -R ollama:ollama /usr/share/ollama

# Create systemd service
log_info "Installing systemd service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

if [[ -f "$CONFIG_DIR/ollama.service" ]]; then
    cp "$CONFIG_DIR/ollama.service" /etc/systemd/system/ollama.service
else
    log_info "Creating default systemd service file"
    cat > /etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"

[Install]
WantedBy=default.target
EOF
fi

# Reload systemd and enable service
log_info "Enabling Ollama service"
systemctl daemon-reload
systemctl enable ollama.service

# Start service
log_info "Starting Ollama service"
systemctl start ollama.service

# Wait for service to be ready
log_info "Waiting for Ollama service to start..."
for i in {1..10}; do
    if systemctl is-active --quiet ollama.service; then
        log_info "✓ Ollama service is running"
        break
    fi
    sleep 1
done

# Verify service status
if ! systemctl is-active --quiet ollama.service; then
    log_error "Ollama service failed to start"
    systemctl status ollama.service --no-pager -l
    exit 1
fi

log_info "✓ Ollama installation completed successfully"
exit 0
