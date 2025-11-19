# Air-Gapped GPU Node - Ollama Deployment

Secure, offline-first deployment system for provisioning Ollama and LLM models to an air-gapped GPU node using CI/CD automation.

## Architecture

```
┌─────────────────────┐         ┌──────────────────┐         ┌─────────────────────┐
│  GitHub Actions     │         │   Deployment     │         │   Air-Gapped GPU    │
│  (Internet Access)  │────────▶│     Bundle       │────────▶│        Node         │
│                     │         │   (tarball)      │         │   (No Internet)     │
│ • Download Ollama   │         │                  │         │                     │
│ • Pull models       │   SSH   │ • Ollama binary  │  Transfer │ • Install Ollama   │
│ • Create bundle     │────────▶│ • Model files    │────────▶│ • Load models       │
│                     │         │ • Scripts        │         │ • Harden system     │
└─────────────────────┘         └──────────────────┘         └─────────────────────┘
```

## Prerequisites

### GPU Node Requirements
- **OS**: RHEL 8/9, Rocky Linux 8/9, or AlmaLinux 8/9
- **CPU**: x86_64 architecture
- **GPU**: NVIDIA GPU with CUDA support (optional but recommended)
- **RAM**: 16GB minimum (32GB+ recommended for larger models)
- **Disk**: 50GB+ free space for models
- **User**: Non-root sudo user for deployment
- **Network**: Air-gapped (no internet), SSH accessible from CI/CD

### CI/CD Requirements
- GitHub repository with Actions enabled
- Self-hosted runner OR GitHub-hosted runner with internet access
- SSH private key for GPU node access

### Required GitHub Secrets

Configure these in your repository settings (`Settings > Secrets and variables > Actions`):

| Secret Name | Description | Example |
|------------|-------------|---------|
| `GPU_NODE_SSH_KEY` | Private SSH key for GPU node | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `GPU_NODE_USER` | Username on GPU node | `deploy-user` |

## Directory Structure

```
opencode/
├── .github/
│   └── workflows/
│       └── deploy-gpu-node.yml     # GitHub Actions workflow
├── scripts/
│   ├── bootstrap-gpu-node.sh       # Main bootstrap orchestrator
│   ├── install-ollama-offline.sh   # Ollama offline installer
│   ├── load-models.sh              # Model loading script
│   └── harden-node.sh              # Security hardening
├── config/
│   └── ollama.service              # Systemd service definition
└── README.md
```

## Deployment Process

### Step 1: Prepare GPU Node

On the GPU node, create a deployment user with sudo access:

```bash
# As root on GPU node
useradd -m -s /bin/bash deploy-user
usermod -aG wheel deploy-user  # Grant sudo access

# Setup SSH key authentication
su - deploy-user
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Step 2: Configure GitHub Secrets

1. Generate SSH key pair (on your workstation):
   ```bash
   ssh-keygen -t ed25519 -f gpu-node-key -C "ci-deploy"
   ```

2. Add public key to GPU node:
   ```bash
   ssh-copy-id -i gpu-node-key.pub deploy-user@gpu-node-ip
   ```

3. Add secrets to GitHub:
   - `GPU_NODE_SSH_KEY`: Contents of `gpu-node-key` (private key)
   - `GPU_NODE_USER`: `deploy-user`

### Step 3: Trigger Deployment

Run the GitHub Actions workflow:

1. Go to `Actions` tab in your repository
2. Select `Deploy Ollama to Air-Gapped GPU Node`
3. Click `Run workflow`
4. Fill in parameters:
   - **Models**: `codellama:7b,codellama:13b` (or other models)
   - **GPU node hostname**: IP address or hostname of GPU node

### Step 4: Monitor Deployment

The workflow will:
1. ✅ Download Ollama installer (v0.5.4)
2. ✅ Pull specified models using temporary Ollama instance
3. ✅ Create deployment bundle (tarball)
4. ✅ Transfer bundle to GPU node via SSH
5. ✅ Execute bootstrap script on GPU node
6. ✅ Verify installation and model availability

Total deployment time: ~15-45 minutes (depending on model sizes)

## Post-Deployment Verification

SSH to the GPU node and verify:

```bash
# Check Ollama service status
sudo systemctl status ollama

# List available models
ollama list

# Test inference
ollama run codellama:7b "Write a Python function to calculate fibonacci"

# Check logs
journalctl -u ollama -f
```

## Security Features

### Implemented Hardening (Standard Level)

- ✅ SSH key-only authentication (no passwords)
- ✅ Root login disabled via SSH
- ✅ Firewall configured (SSH only, Ollama localhost-only)
- ✅ Ollama runs as unprivileged `ollama` user
- ✅ Systemd hardening (NoNewPrivileges, ProtectSystem, etc.)
- ✅ SELinux enforcing (if available)
- ✅ Audit logging for Ollama operations
- ✅ Unnecessary services disabled

### Network Isolation

Ollama listens **only** on `127.0.0.1:11434` (localhost), ensuring:
- No external network exposure
- Models remain on air-gapped node
- API accessible only from localhost

To expose Ollama to other hosts (e.g., for development):

```bash
# WARNING: Only do this if GPU node is on trusted network
sudo systemctl edit ollama

# Add:
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

## Customization

### Use Different Models

Edit the workflow input or modify `.github/workflows/deploy-gpu-node.yml`:

```yaml
models: 'qwen2.5-coder:7b,deepseek-coder-v2:16b'
```

### Adjust Ollama Configuration

Edit `config/ollama.service`:

```ini
# Increase concurrent models
Environment="OLLAMA_MAX_LOADED_MODELS=3"

# Keep models loaded longer
Environment="OLLAMA_KEEP_ALIVE=30m"

# Enable GPU 1 instead of GPU 0
Environment="CUDA_VISIBLE_DEVICES=1"
```

### Change Ollama Version

Edit `.github/workflows/deploy-gpu-node.yml`:

```yaml
env:
  OLLAMA_VERSION: '0.5.4'  # Change to desired version
```

## Troubleshooting

### Deployment Failed - SSH Connection

```bash
# Verify SSH access from your workstation
ssh -i gpu-node-key deploy-user@gpu-node-ip

# Check SSH daemon status on GPU node
sudo systemctl status sshd
```

### Ollama Service Not Starting

```bash
# Check service status
sudo systemctl status ollama

# View detailed logs
sudo journalctl -u ollama -n 100 --no-pager

# Check binary
/usr/local/bin/ollama --version

# Test manually
sudo -u ollama /usr/local/bin/ollama serve
```

### Models Not Loading

```bash
# Check models directory
ls -lh /usr/share/ollama/.ollama/models/

# Verify ownership
sudo chown -R ollama:ollama /usr/share/ollama

# Check disk space
df -h /usr/share/ollama

# Manually verify model integrity
ollama list
```

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Verify CUDA libraries
ldconfig -p | grep cuda

# Enable CUDA in systemd service
sudo systemctl edit ollama
# Add: Environment="CUDA_VISIBLE_DEVICES=0"

sudo systemctl restart ollama
```

### Firewall Blocking Access

```bash
# Check firewall status
sudo firewall-cmd --list-all

# Verify Ollama is listening
sudo ss -tlnp | grep 11434

# Test local connectivity
curl http://127.0.0.1:11434/api/version
```

## Re-deployment / Updates

To update models or Ollama version:

1. Modify workflow parameters or `OLLAMA_VERSION`
2. Re-run the workflow
3. The bootstrap script is **idempotent** and safe to re-run

To rollback:
```bash
# Stop service
sudo systemctl stop ollama

# Remove installation
sudo rm /usr/local/bin/ollama
sudo rm -rf /usr/share/ollama/.ollama/models/*

# Re-run deployment with previous version
```

## Manual Offline Deployment

If CI/CD is unavailable, deploy manually:

1. On a machine with internet, download artifacts:
   ```bash
   # Download Ollama
   curl -fsSL https://github.com/ollama/ollama/releases/download/v0.5.4/ollama-linux-amd64 -o ollama

   # Pull models
   ollama serve &
   ollama pull codellama:7b
   tar -czf models.tar.gz ~/.ollama/models/
   ```

2. Transfer to GPU node:
   ```bash
   scp ollama models.tar.gz scripts/ config/ deploy-user@gpu-node:/tmp/
   ```

3. Execute bootstrap:
   ```bash
   ssh deploy-user@gpu-node
   cd /tmp
   sudo scripts/bootstrap-gpu-node.sh
   ```

## Cost Optimization

- **Use self-hosted runners** for CI/CD to avoid GitHub Actions minutes
- **Cache model downloads** in a separate artifact repository
- **Compress models** with `zstd` for faster transfers (decompress on GPU node)

## Support & Contributing

For issues or improvements:
1. Check logs: `journalctl -u ollama -f`
2. Verify scripts are executable: `chmod +x scripts/*.sh`
3. Test offline mode: Disconnect network and verify operations

## License

This deployment system is provided as-is for air-gapped GPU provisioning.

---

**Generated for**: RHEL/Rocky/AlmaLinux | CodeLlama Models | GitHub Actions | Standard Security
