#!/bin/bash
#
# Verification script for air-gapped GPU node deployment
# Run this on the GPU node after deployment
#
# Usage: ./verify-deployment.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "=== Air-Gapped GPU Node Deployment Verification ==="
echo ""

# Check 1: Ollama binary
echo "[1/10] Checking Ollama binary..."
if [[ -f /usr/local/bin/ollama ]] && [[ -x /usr/local/bin/ollama ]]; then
    VERSION=$(/usr/local/bin/ollama --version 2>&1 | head -n1)
    check_pass "Ollama binary installed: $VERSION"
else
    check_fail "Ollama binary not found or not executable"
fi

# Check 2: Ollama user
echo "[2/10] Checking ollama user..."
if id ollama &>/dev/null; then
    check_pass "User 'ollama' exists"
else
    check_fail "User 'ollama' does not exist"
fi

# Check 3: Systemd service
echo "[3/10] Checking systemd service..."
if systemctl is-enabled ollama.service &>/dev/null; then
    check_pass "Ollama service is enabled"
else
    check_fail "Ollama service is not enabled"
fi

if systemctl is-active ollama.service &>/dev/null; then
    check_pass "Ollama service is running"
else
    check_fail "Ollama service is not running"
fi

# Check 4: Models directory
echo "[4/10] Checking models directory..."
MODELS_DIR="/usr/share/ollama/.ollama/models"
if [[ -d "$MODELS_DIR" ]]; then
    MODEL_COUNT=$(find "$MODELS_DIR" -type f | wc -l)
    DISK_USAGE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
    check_pass "Models directory exists ($DISK_USAGE, $MODEL_COUNT files)"
else
    check_fail "Models directory not found"
fi

# Check 5: Ollama API
echo "[5/10] Checking Ollama API..."
if curl -s http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    check_pass "Ollama API is responding"
else
    check_fail "Ollama API not responding on localhost:11434"
fi

# Check 6: Model list
echo "[6/10] Checking available models..."
if command -v ollama &>/dev/null; then
    MODEL_LIST=$(ollama list 2>/dev/null | tail -n +2)
    if [[ -n "$MODEL_LIST" ]]; then
        check_pass "Models loaded:"
        echo "$MODEL_LIST" | while read line; do
            echo "    $line"
        done
    else
        check_fail "No models found"
    fi
else
    check_fail "Ollama command not in PATH"
fi

# Check 7: GPU availability
echo "[7/10] Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    if nvidia-smi >/dev/null 2>&1; then
        GPU_INFO=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -n1)
        check_pass "GPU available: $GPU_INFO"
    else
        check_warn "nvidia-smi failed - driver issue?"
    fi
else
    check_warn "nvidia-smi not found - running in CPU-only mode"
fi

# Check 8: Firewall
echo "[8/10] Checking firewall..."
if command -v firewall-cmd &>/dev/null; then
    if firewall-cmd --state &>/dev/null; then
        check_pass "Firewalld is running"
        ALLOWED_SERVICES=$(firewall-cmd --list-services 2>/dev/null)
        echo "    Allowed services: $ALLOWED_SERVICES"
    else
        check_warn "Firewalld not running"
    fi
else
    check_warn "Firewalld not installed"
fi

# Check 9: SSH hardening
echo "[9/10] Checking SSH hardening..."
if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
    check_pass "Root login disabled"
else
    check_warn "Root login may be enabled"
fi

if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
    check_pass "Password authentication disabled"
else
    check_warn "Password authentication may be enabled"
fi

# Check 10: Network isolation
echo "[10/10] Checking network isolation..."
if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    check_warn "Internet connectivity detected - is this truly air-gapped?"
else
    check_pass "No internet connectivity (air-gapped confirmed)"
fi

# Summary
echo ""
echo "=== Verification Summary ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  • Test inference: ollama run codellama:7b 'write a hello world function'"
    echo "  • Monitor logs: journalctl -u ollama -f"
    echo "  • Check resources: nvidia-smi (if GPU available)"
    exit 0
else
    echo -e "${RED}✗ Some checks failed - review errors above${NC}"
    exit 1
fi
