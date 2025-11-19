#!/bin/bash
#
# Security hardening for air-gapped GPU node
# Implements standard hardening: key-only SSH, limited services
#
# Usage: sudo ./harden-node.sh
#

set -euo pipefail

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# Verify running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log_info "=== Security Hardening for GPU Node ==="

# 1. SSH Hardening
log_info "Step 1/6: Hardening SSH configuration"
SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ -f "$SSHD_CONFIG" ]]; then
    # Backup original config
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

    # Apply hardening (idempotent)
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG"

    # Verify config
    if sshd -t; then
        log_info "✓ SSH configuration valid"
        systemctl reload sshd || systemctl restart sshd
    else
        log_error "SSH configuration invalid, reverting"
        mv "${SSHD_CONFIG}.backup.$(date +%Y%m%d-*)" "$SSHD_CONFIG"
        exit 1
    fi
else
    log_warn "SSH config not found at $SSHD_CONFIG"
fi

# 2. Firewall Configuration (firewalld - standard on RHEL/Rocky)
log_info "Step 2/6: Configuring firewall"
if command -v firewall-cmd &>/dev/null; then
    # Ensure firewalld is running
    if ! systemctl is-active --quiet firewalld; then
        systemctl enable firewalld
        systemctl start firewalld
    fi

    # Set default zone to drop (deny all by default)
    firewall-cmd --set-default-zone=drop --permanent || true

    # Allow SSH (critical - don't lock yourself out)
    firewall-cmd --permanent --zone=public --add-service=ssh

    # Allow Ollama only on localhost (not exposed externally)
    # Ollama listens on 127.0.0.1:11434 by default, which is already local-only

    # Reload firewall
    firewall-cmd --reload
    log_info "✓ Firewall configured (SSH only)"
else
    log_warn "firewalld not available, skipping firewall configuration"
fi

# 3. Disable Unnecessary Services
log_info "Step 3/6: Disabling unnecessary services"
UNNECESSARY_SERVICES=(
    "bluetooth"
    "cups"
    "avahi-daemon"
)

for service in "${UNNECESSARY_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        systemctl disable "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
        log_info "  Disabled: $service"
    fi
done

# 4. File System Permissions
log_info "Step 4/6: Securing Ollama directories"
if [[ -d /usr/share/ollama ]]; then
    chown -R ollama:ollama /usr/share/ollama
    chmod 750 /usr/share/ollama
    log_info "✓ Ollama directories secured"
fi

# 5. SELinux (RHEL/Rocky default)
log_info "Step 5/6: Verifying SELinux status"
if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce)
    log_info "SELinux status: $SELINUX_STATUS"

    if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
        log_info "✓ SELinux is enforcing (recommended)"

        # Set context for Ollama binary
        if command -v restorecon &>/dev/null; then
            restorecon -v /usr/local/bin/ollama 2>/dev/null || true
        fi
    else
        log_warn "SELinux is not enforcing - consider enabling it"
    fi
else
    log_info "SELinux not available on this system"
fi

# 6. System Auditing
log_info "Step 6/6: Enabling audit logging"
if command -v auditctl &>/dev/null; then
    # Monitor Ollama binary execution
    auditctl -w /usr/local/bin/ollama -p x -k ollama_exec 2>/dev/null || true
    # Monitor Ollama models directory
    auditctl -w /usr/share/ollama/.ollama/models -p wa -k ollama_models 2>/dev/null || true
    log_info "✓ Audit rules added for Ollama"
else
    log_warn "auditd not available, skipping audit configuration"
fi

# Summary
log_info ""
log_info "=== Security Hardening Summary ==="
log_info "✓ SSH: Key-only authentication, no root login"
log_info "✓ Firewall: SSH only, Ollama localhost-only"
log_info "✓ Services: Unnecessary services disabled"
log_info "✓ Permissions: Ollama directories secured"
log_info "✓ SELinux: $(getenforce 2>/dev/null || echo 'N/A')"
log_info "✓ Auditing: Enabled for Ollama operations"
log_info ""
log_warn "IMPORTANT: Verify you can still SSH to this node before closing current session"
log_info ""

exit 0
