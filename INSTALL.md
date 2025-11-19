# OpenCode Installation & Execution Guide

Complete step-by-step guide to install and run the air-gapped GPU node deployment system.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Running the Deployment](#running-the-deployment)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## System Requirements

### GPU Node (Target Machine)
- **Operating System**: RHEL 8/9, Rocky Linux 8/9, or AlmaLinux 8/9
- **Architecture**: x86_64
- **RAM**: 16GB minimum (32GB+ recommended)
- **Storage**: 50GB+ free disk space
- **GPU**: NVIDIA GPU with CUDA support (optional but recommended)
- **Network**: Air-gapped (no internet), but SSH accessible from CI/CD
- **User**: Non-root user with sudo privileges

### CI/CD Environment (GitHub Actions)
- GitHub account with repository access
- GitHub Actions enabled
- Internet connectivity (for downloading Ollama and models)

### Your Workstation
- Git installed
- SSH client
- Access to GPU node via SSH
- GitHub account credentials

---

## Installation

### Step 1: Clone the Repository

On your workstation:

```bash
# Clone the repository
git clone git@github.com:moghimis/opencode-instalation.git
cd opencode-instalation

# Verify contents
ls -la
```

**Expected output:**
```
.github/
config/
scripts/
.gitignore
INSTALL.md
QUICKSTART.md
README.md
```

### Step 2: Prepare the GPU Node

SSH to your GPU node and create a deployment user:

```bash
# SSH to GPU node as root or admin user
ssh admin@YOUR_GPU_NODE_IP

# Create deployment user
sudo useradd -m -s /bin/bash deploy-user

# Add to sudo group (wheel on RHEL/Rocky)
sudo usermod -aG wheel deploy-user

# Verify user creation
id deploy-user
```

**Expected output:**
```
uid=1001(deploy-user) gid=1001(deploy-user) groups=1001(deploy-user),10(wheel)
```

### Step 3: Setup SSH Key Authentication

On your workstation:

```bash
# Generate SSH key pair for deployment
ssh-keygen -t ed25519 -f ~/.ssh/gpu-node-deploy -C "gpu-node-deployment" -N ""

# Copy public key to GPU node
ssh-copy-id -i ~/.ssh/gpu-node-deploy.pub deploy-user@YOUR_GPU_NODE_IP

# Test SSH connection
ssh -i ~/.ssh/gpu-node-deploy deploy-user@YOUR_GPU_NODE_IP "hostname && whoami"
```

**Expected output:**
```
your-gpu-node-hostname
deploy-user
```

If successful, exit the SSH session:
```bash
exit
```

### Step 4: Verify GPU Node Prerequisites

SSH back to the GPU node and check:

```bash
ssh -i ~/.ssh/gpu-node-deploy deploy-user@YOUR_GPU_NODE_IP

# Check OS version
cat /etc/os-release | grep -E "NAME|VERSION"

# Check disk space
df -h /

# Check sudo access
sudo whoami

# Check if internet is blocked (should fail or timeout)
timeout 5 ping -c 1 8.8.8.8 || echo "Confirmed: Air-gapped"

# Check GPU (if applicable)
nvidia-smi || echo "No GPU or drivers not installed"

# Exit GPU node
exit
```

---

## Configuration

### Step 5: Configure GitHub Repository Secrets

1. **Navigate to repository settings:**
   - Go to: https://github.com/moghimis/opencode-instalation
   - Click: `Settings` → `Secrets and variables` → `Actions`
   - Click: `New repository secret`

2. **Add GPU_NODE_SSH_KEY:**

   On your workstation:
   ```bash
   # Display private key
   cat ~/.ssh/gpu-node-deploy
   ```

   Copy the **entire output** including:
   ```
   -----BEGIN OPENSSH PRIVATE KEY-----
   ... (all content) ...
   -----END OPENSSH PRIVATE KEY-----
   ```

   - Name: `GPU_NODE_SSH_KEY`
   - Secret: Paste the private key content
   - Click: `Add secret`

3. **Add GPU_NODE_USER:**

   - Click: `New repository secret`
   - Name: `GPU_NODE_USER`
   - Secret: `deploy-user`
   - Click: `Add secret`

4. **Verify secrets are added:**
   - You should see 2 secrets listed:
     - `GPU_NODE_SSH_KEY`
     - `GPU_NODE_USER`

### Step 6: Review Workflow Configuration (Optional)

Check the workflow file to understand what will happen:

```bash
cat .github/workflows/deploy-gpu-node.yml
```

**Key settings you can customize:**
- `OLLAMA_VERSION`: Default is `0.5.4`
- Models: Specified at runtime (default: `codellama:7b,codellama:13b`)

---

## Running the Deployment

### Step 7: Trigger the Deployment Workflow

1. **Go to GitHub Actions:**
   - Navigate to: https://github.com/moghimis/opencode-instalation/actions
   - Click: `Deploy Ollama to Air-Gapped GPU Node`

2. **Run the workflow:**
   - Click: `Run workflow` (dropdown button on the right)
   - Configure inputs:
     - **Models to download**: `codellama:7b,codellama:13b`
     - **GPU node hostname/IP**: `YOUR_GPU_NODE_IP` (e.g., `192.168.1.100`)
   - Click: `Run workflow` (green button)

3. **Monitor the workflow:**
   - The workflow will appear in the list
   - Click on it to see detailed logs
   - Watch the progress through these stages:
     1. ✅ Build offline bundle (5-30 minutes)
     2. ✅ Deploy to GPU node (2-5 minutes)
     3. ✅ Verify deployment (1 minute)

**Total time:** 15-45 minutes depending on model sizes and network speed

### Step 8: Monitor Deployment Progress

In the GitHub Actions UI, you'll see these jobs:

**Job 1: build-offline-bundle**
```
✓ Checkout repository
✓ Create bundle directory structure
✓ Download Ollama installer
✓ Pull models using Ollama
✓ Copy deployment scripts
✓ Create tarball
✓ Upload artifact
```

**Job 2: deploy-to-gpu-node**
```
✓ Download artifact
✓ Verify checksum
✓ Setup SSH key
✓ Transfer bundle to GPU node
✓ Execute bootstrap on GPU node
✓ Verify deployment
```

---

## Verification

### Step 9: Verify Deployment on GPU Node

SSH to the GPU node:

```bash
ssh -i ~/.ssh/gpu-node-deploy deploy-user@YOUR_GPU_NODE_IP
```

**Method 1: Automated verification**

```bash
# Find the verification script
find /tmp -name "verify-deployment.sh" -type f 2>/dev/null

# If found in deployment bundle:
sudo /tmp/deployment-bundle/scripts/verify-deployment.sh

# Or if already installed:
sudo /usr/local/bin/verify-deployment.sh
```

**Expected output:**
```
=== Air-Gapped GPU Node Deployment Verification ===

✓ Ollama binary installed: ollama version 0.5.4
✓ User 'ollama' exists
✓ Ollama service is enabled
✓ Ollama service is running
✓ Models directory exists (11G, 234 files)
✓ Ollama API is responding
✓ Models loaded:
    codellama:7b    3.8 GB
    codellama:13b   7.3 GB
✓ GPU available: NVIDIA A100-SXM4-40GB
✓ No internet connectivity (air-gapped confirmed)

Passed: 10
Failed: 0

✓ All critical checks passed!
```

**Method 2: Manual verification**

```bash
# Check Ollama service status
sudo systemctl status ollama

# List available models
ollama list

# Test model inference
ollama run codellama:7b "def fibonacci(n):"

# Check GPU usage (if GPU available)
nvidia-smi

# View logs
sudo journalctl -u ollama -n 50 --no-pager
```

### Step 10: Test Model Inference

```bash
# Simple code generation test
ollama run codellama:7b "Write a Python function to calculate factorial"

# Code completion test
ollama run codellama:7b "def reverse_string(s):"

# Multi-line code test
ollama run codellama:13b "Create a REST API endpoint using Flask for user authentication"
```

**Expected behavior:**
- Model loads (may take 5-30 seconds on first run)
- Code is generated
- GPU utilization increases (check with `nvidia-smi`)

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Workflow fails at "Transfer bundle to GPU node"

**Symptom:**
```
Permission denied (publickey)
```

**Solution:**
```bash
# Verify SSH key is correctly added to GitHub secrets
# Test SSH connection manually
ssh -i ~/.ssh/gpu-node-deploy deploy-user@YOUR_GPU_NODE_IP

# If this fails, re-copy the public key
ssh-copy-id -i ~/.ssh/gpu-node-deploy.pub deploy-user@YOUR_GPU_NODE_IP
```

#### Issue 2: Ollama service fails to start

**Symptom:**
```
✗ Ollama service is not running
```

**Solution:**
```bash
# Check service logs
sudo journalctl -u ollama -n 100 --no-pager

# Check binary
/usr/local/bin/ollama --version

# Try starting manually
sudo systemctl start ollama
sudo systemctl status ollama

# Check permissions
sudo chown -R ollama:ollama /usr/share/ollama
```

#### Issue 3: Models not appearing

**Symptom:**
```
ollama list
# Shows empty or "no models found"
```

**Solution:**
```bash
# Check models directory
ls -lh /usr/share/ollama/.ollama/models/

# Check ownership
sudo chown -R ollama:ollama /usr/share/ollama/.ollama/models/

# Restart Ollama
sudo systemctl restart ollama

# Wait a few seconds and try again
sleep 5
ollama list
```

#### Issue 4: GPU not detected

**Symptom:**
```
⚠ nvidia-smi not found
```

**Solution:**
```bash
# Install NVIDIA drivers (requires internet on initial setup)
# This must be done before air-gapping the node

# Check if drivers are installed
lsmod | grep nvidia

# Check CUDA installation
ls -la /usr/local/cuda/

# Update systemd service to use GPU
sudo systemctl edit ollama
# Add:
# [Service]
# Environment="CUDA_VISIBLE_DEVICES=0"

sudo systemctl restart ollama
```

#### Issue 5: Disk space full

**Symptom:**
```
No space left on device
```

**Solution:**
```bash
# Check disk usage
df -h
du -sh /usr/share/ollama/.ollama/models/

# Clean up old deployment bundles
rm -rf /tmp/deployment-bundle
rm -f /tmp/gpu-node-deployment.tar.gz

# Remove unused models
ollama rm model-name:tag
```

#### Issue 6: Firewall blocking localhost access

**Symptom:**
```
curl: (7) Failed to connect to 127.0.0.1 port 11434
```

**Solution:**
```bash
# Check if Ollama is listening
sudo ss -tlnp | grep 11434

# Check firewall (should allow localhost)
sudo firewall-cmd --list-all

# Verify Ollama host configuration
sudo systemctl cat ollama | grep OLLAMA_HOST
# Should show: Environment="OLLAMA_HOST=127.0.0.1:11434"

# Restart service
sudo systemctl restart ollama
```

---

## Post-Installation Tasks

### Using Ollama from Applications

**Local API calls:**
```bash
# Generate code
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "codellama:7b",
  "prompt": "Write a function to sort an array",
  "stream": false
}'
```

**From Python:**
```python
import requests

response = requests.post('http://127.0.0.1:11434/api/generate', json={
    'model': 'codellama:7b',
    'prompt': 'def quicksort(arr):',
    'stream': False
})

print(response.json()['response'])
```

### Monitoring and Maintenance

```bash
# Monitor service logs
sudo journalctl -u ollama -f

# Monitor GPU usage
watch -n 1 nvidia-smi

# Monitor disk usage
watch -n 60 df -h /usr/share/ollama

# Check service uptime
systemctl status ollama | grep Active
```

### Updating Models

To add or update models, re-run the GitHub Actions workflow with different model parameters:

1. Go to Actions → Deploy Ollama to Air-Gapped GPU Node
2. Click Run workflow
3. Change models: `codellama:7b,qwen2.5-coder:7b,deepseek-coder-v2:16b`
4. Enter GPU node IP
5. Run workflow

The deployment is idempotent - it will safely update existing installation.

---

## Quick Reference

### Essential Commands

```bash
# Service management
sudo systemctl status ollama
sudo systemctl restart ollama
sudo journalctl -u ollama -f

# Model operations
ollama list
ollama run model-name:tag "prompt"
ollama rm model-name:tag

# System checks
nvidia-smi
df -h /usr/share/ollama
ss -tlnp | grep 11434

# Verification
curl http://127.0.0.1:11434/api/version
```

### Important Paths

- **Ollama binary**: `/usr/local/bin/ollama`
- **Models directory**: `/usr/share/ollama/.ollama/models/`
- **Service file**: `/etc/systemd/system/ollama.service`
- **Logs**: `journalctl -u ollama`

### GitHub Workflow URLs

- **Actions**: https://github.com/moghimis/opencode-instalation/actions
- **Workflow file**: `.github/workflows/deploy-gpu-node.yml`
- **Secrets**: https://github.com/moghimis/opencode-instalation/settings/secrets/actions

---

## Need Help?

1. Check logs: `sudo journalctl -u ollama -n 100 --no-pager`
2. Run verification: `sudo verify-deployment.sh`
3. Review [README.md](README.md) for detailed architecture
4. Review [QUICKSTART.md](QUICKSTART.md) for condensed guide

---

**Installation complete!** Your air-gapped GPU node is now running Ollama with local models.
