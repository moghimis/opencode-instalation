# Quick Start Guide

Deploy Ollama to an air-gapped GPU node in 5 minutes.

## Prerequisites Checklist

- [ ] GPU node running RHEL/Rocky/AlmaLinux 8/9
- [ ] Non-root sudo user on GPU node
- [ ] SSH access from CI/CD to GPU node
- [ ] GitHub repository with Actions enabled
- [ ] 50GB+ free disk space on GPU node

## Step-by-Step Deployment

### 1. Configure SSH Access (On GPU Node)

```bash
# Create deployment user
sudo useradd -m -s /bin/bash deploy-user
sudo usermod -aG wheel deploy-user

# Setup SSH directory
sudo su - deploy-user
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

### 2. Generate SSH Keys (On Your Workstation)

```bash
# Generate key pair
ssh-keygen -t ed25519 -f ~/.ssh/gpu-node-key -C "ci-deploy" -N ""

# Copy public key to GPU node
ssh-copy-id -i ~/.ssh/gpu-node-key.pub deploy-user@YOUR_GPU_NODE_IP

# Test connection
ssh -i ~/.ssh/gpu-node-key deploy-user@YOUR_GPU_NODE_IP
```

### 3. Add GitHub Secrets

Go to: `Settings > Secrets and variables > Actions > New repository secret`

Add two secrets:

1. **GPU_NODE_SSH_KEY**
   ```bash
   cat ~/.ssh/gpu-node-key  # Copy entire output including headers
   ```

2. **GPU_NODE_USER**
   ```
   deploy-user
   ```

### 4. Run Deployment

1. Go to `Actions` tab in GitHub
2. Click `Deploy Ollama to Air-Gapped GPU Node`
3. Click `Run workflow`
4. Enter:
   - **Models**: `codellama:7b,codellama:13b`
   - **GPU node hostname**: `YOUR_GPU_NODE_IP`
5. Click `Run workflow` (green button)

Deployment takes 15-45 minutes depending on model sizes.

### 5. Verify Deployment

SSH to GPU node and run:

```bash
# Quick verification
./deployment-bundle/scripts/verify-deployment.sh

# OR manual checks:
systemctl status ollama
ollama list
ollama run codellama:7b "def fibonacci(n):"
```

## Expected Output

```
✓ Ollama binary installed: ollama version 0.5.4
✓ Ollama service is running
✓ Models loaded:
    codellama:7b     3.8 GB
    codellama:13b    7.3 GB
✓ GPU available: NVIDIA A100-SXM4-40GB
✓ Air-gapped confirmed
```

## Troubleshooting

### Deployment fails at "Transfer bundle to GPU node"

**Cause**: SSH connection issue

**Fix**:
```bash
# Test SSH manually
ssh -i ~/.ssh/gpu-node-key deploy-user@YOUR_GPU_NODE_IP

# Check known_hosts
ssh-keyscan YOUR_GPU_NODE_IP >> ~/.ssh/known_hosts
```

### Ollama service not starting

**Cause**: Binary incompatible or permissions issue

**Fix**:
```bash
# Check logs
sudo journalctl -u ollama -n 50

# Verify binary
/usr/local/bin/ollama --version

# Check permissions
sudo chown -R ollama:ollama /usr/share/ollama
```

### Models not appearing

**Cause**: Model files not copied correctly

**Fix**:
```bash
# Check models directory
ls -lh /usr/share/ollama/.ollama/models/

# Check disk space
df -h /usr/share/ollama

# Re-run model loading
sudo /tmp/deployment-bundle/scripts/load-models.sh /tmp/deployment-bundle/models
```

## What's Next?

- **Use Ollama**: `curl http://localhost:11434/api/generate -d '{"model":"codellama:7b","prompt":"your code"}'`
- **Monitor logs**: `journalctl -u ollama -f`
- **Check GPU usage**: `watch -n 1 nvidia-smi`
- **Update models**: Re-run workflow with different model list
- **Read full docs**: See [README.md](README.md) for advanced configuration

## Security Notes

- Ollama listens **only on localhost** (127.0.0.1:11434)
- SSH is key-only (no passwords)
- Root login disabled
- Firewall blocks all except SSH
- Runs as unprivileged `ollama` user

To expose Ollama to network (dev only):
```bash
sudo systemctl edit ollama
# Add: Environment="OLLAMA_HOST=0.0.0.0:11434"
sudo systemctl restart ollama
```

**WARNING**: Only do this on trusted networks!

---

Need help? Check [README.md](README.md) for detailed documentation.
