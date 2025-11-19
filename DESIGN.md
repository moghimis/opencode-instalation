# OpenCode System Design

Architectural design document for the air-gapped GPU node deployment system.

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [System Architecture](#system-architecture)
4. [Component Design](#component-design)
5. [Security Architecture](#security-architecture)
6. [Deployment Flow](#deployment-flow)
7. [Data Flow](#data-flow)
8. [Technology Stack](#technology-stack)
9. [Design Decisions](#design-decisions)
10. [Future Enhancements](#future-enhancements)

---

## Overview

### Purpose

The OpenCode system is designed to provision Ollama (local LLM inference engine) and language models onto completely isolated, air-gapped GPU nodes without requiring any internet connectivity on the target infrastructure.

### Problem Statement

Traditional deployment methods assume continuous internet connectivity for:
- Package downloads (`curl`, `wget`, `apt`)
- Model pulling from registries
- Dependency resolution
- Software updates

Air-gapped environments (data centers, secure facilities, edge computing) cannot use these methods, creating a deployment gap for AI infrastructure.

### Solution

A two-phase deployment system that:
1. **Phase 1 (Internet-connected CI/CD)**: Bundles all required artifacts
2. **Phase 2 (Air-gapped target)**: Deploys from local bundle with zero external dependencies

---

## Design Principles

### 1. Zero Trust Networking

**Principle**: Assume the GPU node has absolutely no network connectivity except controlled SSH.

**Implementation**:
- No `curl`, `wget`, `apt update`, or package repository access
- All artifacts pre-fetched and transferred as a single bundle
- Checksum verification at every stage
- Offline-safe scripts that fail fast if network calls are attempted

### 2. Idempotency

**Principle**: All deployment operations can be run multiple times safely.

**Implementation**:
- Scripts check existing state before making changes
- User/group creation uses conditional logic (`id -u user || useradd`)
- Service installation overwrites cleanly
- Model loading skips existing files
- Redeployments update in-place without data loss

### 3. Determinism

**Principle**: Same inputs always produce same outputs.

**Implementation**:
- Pinned Ollama version (`OLLAMA_VERSION: '0.5.4'`)
- Explicit model versions in workflow inputs
- No automatic updates or latest tags
- Reproducible builds with checksums
- Version metadata stored in deployment bundle

### 4. Defense in Depth

**Principle**: Multiple layers of security controls.

**Implementation**:
- Network: Firewall rules, localhost-only binding
- Authentication: SSH key-only, no passwords, no root login
- Authorization: Unprivileged service user, sudo boundaries
- System: SELinux, systemd sandboxing, audit logging
- Application: Minimal surface area, read-only filesystems

### 5. Fail-Safe Defaults

**Principle**: Secure by default, explicit to relax.

**Implementation**:
- Ollama listens only on `127.0.0.1:11434` (localhost)
- SSH root login disabled
- Firewall drops all except SSH
- Service runs as `ollama` user (not root)
- All scripts exit on error (`set -euo pipefail`)

### 6. Separation of Concerns

**Principle**: Each component has a single, well-defined responsibility.

**Implementation**:
- `bootstrap-gpu-node.sh`: Orchestration only
- `install-ollama-offline.sh`: Binary installation
- `load-models.sh`: Model deployment
- `harden-node.sh`: Security configuration
- `verify-deployment.sh`: Post-deployment validation

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CI/CD Layer                              │
│                    (Internet-Connected)                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              GitHub Actions Workflow                     │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│  │  │   Download   │  │  Pull Models │  │    Create    │  │   │
│  │  │    Ollama    │→ │  (Temporary) │→ │   Bundle     │  │   │
│  │  │    Binary    │  │    Ollama    │  │  (Tarball)   │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ SSH Transfer
                              │ (One-way, Authenticated)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Air-Gapped GPU Node                           │
│                   (Zero Internet Access)                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Deployment Bundle                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│  │  │    Ollama    │  │    Model     │  │   Scripts    │  │   │
│  │  │    Binary    │  │    Files     │  │    Config    │  │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │           Bootstrap Orchestration                        │   │
│  │    ┌───────────┐  ┌───────────┐  ┌───────────┐         │   │
│  │    │  Install  │→ │   Load    │→ │  Harden   │         │   │
│  │    │  Ollama   │  │  Models   │  │  System   │         │   │
│  │    └───────────┘  └───────────┘  └───────────┘         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Running Ollama Service                      │   │
│  │    • Systemd-managed                                     │   │
│  │    • Localhost-only (127.0.0.1:11434)                   │   │
│  │    • Models: /usr/share/ollama/.ollama/models/          │   │
│  │    • User: ollama (unprivileged)                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                       External Network                          │
│              (Blocked by air-gap/firewall)                      │
└────────────────────────────────────────────────────────────────┘
                              ╳ No Connection
                              ╳
┌────────────────────────────────────────────────────────────────┐
│                  Management Network (SSH Only)                  │
│                                                                  │
│  ┌──────────────────┐              ┌──────────────────┐        │
│  │   CI/CD Runner   │──── SSH ────▶│    GPU Node      │        │
│  │  (GitHub Actions)│   Port 22    │  (Air-gapped)    │        │
│  └──────────────────┘              └──────────────────┘        │
└────────────────────────────────────────────────────────────────┘

GPU Node Internal:
  ┌─────────────────────────────────────┐
  │  Firewall (firewalld)                │
  │  • Default: DROP                     │
  │  • Allow: SSH (port 22)              │
  │  • Block: All outbound               │
  └─────────────────────────────────────┘
                │
                ▼
  ┌─────────────────────────────────────┐
  │  Localhost Services                  │
  │  • Ollama: 127.0.0.1:11434          │
  │  • Not exposed externally            │
  └─────────────────────────────────────┘
```

---

## Component Design

### 1. GitHub Actions Workflow

**File**: `.github/workflows/deploy-gpu-node.yml`

**Responsibilities**:
- Artifact acquisition from internet sources
- Model downloading and bundling
- Bundle transfer orchestration
- Remote execution coordination

**Design**:

```yaml
Job 1: build-offline-bundle
  ├─ Download Ollama binary (specific version)
  ├─ Install temporary Ollama (on CI runner)
  ├─ Pull models using temporary instance
  ├─ Copy models from ~/.ollama/models/
  ├─ Bundle: installers/ + models/ + scripts/ + config/
  ├─ Create tarball with checksums
  └─ Upload artifact (GitHub artifact storage)

Job 2: deploy-to-gpu-node
  ├─ Download artifact
  ├─ Verify checksum (fail if tampered)
  ├─ Setup SSH authentication
  ├─ Transfer tarball to /tmp/ on GPU node
  ├─ Execute bootstrap script via SSH
  └─ Verify deployment success
```

**Key Features**:
- Two-job pipeline for separation of concerns
- Artifact-based handoff (enables auditing)
- Checksum verification (integrity)
- Parallel-safe (multiple deployments can run)

### 2. Bootstrap Orchestrator

**File**: `scripts/bootstrap-gpu-node.sh`

**Responsibilities**:
- Execute deployment phases in correct order
- Verify bundle integrity
- Coordinate sub-scripts
- Report status

**Design**:

```bash
Phase 1: Verify Bundle
  ├─ Check directory structure
  ├─ Verify Ollama binary exists
  └─ Verify models directory populated

Phase 2: Check Air-gap Status
  └─ Test internet connectivity (should fail)

Phase 3: Install Ollama
  └─ Call install-ollama-offline.sh

Phase 4: Load Models
  └─ Call load-models.sh

Phase 5: Security Hardening
  └─ Call harden-node.sh
```

**Error Handling**:
- `set -euo pipefail` ensures any failure stops execution
- Colored logging for visibility
- Exit codes propagate to CI/CD

### 3. Ollama Installer

**File**: `scripts/install-ollama-offline.sh`

**Responsibilities**:
- Create system user
- Install binary
- Configure systemd service
- Start and enable service

**Design**:

```bash
Step 1: User Management
  ├─ Check if 'ollama' user exists
  ├─ Create user if missing (unprivileged, no shell)
  └─ Create home directory: /usr/share/ollama

Step 2: Binary Installation
  ├─ Verify binary is executable
  ├─ Install to /usr/local/bin/ollama
  └─ Set ownership: root:root, mode: 755

Step 3: Systemd Service
  ├─ Copy ollama.service to /etc/systemd/system/
  ├─ Reload systemd daemon
  ├─ Enable service (start on boot)
  └─ Start service

Step 4: Verification
  ├─ Check service status
  ├─ Wait for API readiness
  └─ Report success/failure
```

### 4. Model Loader

**File**: `scripts/load-models.sh`

**Responsibilities**:
- Copy models from bundle to Ollama's directory
- Set correct ownership and permissions
- Restart Ollama to index models

**Design**:

```bash
Step 1: Validation
  ├─ Verify source models directory exists
  └─ Count model files (fail if zero)

Step 2: Service Management
  ├─ Stop Ollama (prevent conflicts)
  └─ Set flag for restart

Step 3: Model Transfer
  ├─ Use rsync for efficient copy
  ├─ Exclude manifest.txt
  └─ Preserve permissions

Step 4: Ownership
  ├─ Recursive chown to ollama:ollama
  └─ Set directory permissions: 755, files: 644

Step 5: Service Restart
  ├─ Start Ollama
  ├─ Wait for indexing
  └─ Verify models appear in 'ollama list'
```

### 5. Security Hardener

**File**: `scripts/harden-node.sh`

**Responsibilities**:
- Apply OS-level security controls
- Configure firewall
- Harden SSH
- Enable auditing

**Design**:

```bash
Step 1: SSH Hardening
  ├─ Backup sshd_config
  ├─ Disable root login
  ├─ Disable password authentication
  ├─ Enable key-only authentication
  ├─ Disable X11 forwarding
  └─ Reload SSH daemon

Step 2: Firewall Configuration
  ├─ Enable firewalld
  ├─ Set default zone: drop (deny all)
  ├─ Allow SSH (port 22)
  └─ Reload firewall

Step 3: Service Minimization
  └─ Disable unnecessary services (bluetooth, cups, avahi)

Step 4: File Permissions
  ├─ Secure /usr/share/ollama (750)
  └─ Restrict ownership to ollama:ollama

Step 5: SELinux
  ├─ Verify SELinux is enforcing
  └─ Set correct context on Ollama binary

Step 6: Audit Logging
  ├─ Add audit rule for Ollama binary execution
  └─ Add audit rule for model directory access
```

### 6. Systemd Service

**File**: `config/ollama.service`

**Responsibilities**:
- Define service lifecycle
- Apply systemd-level sandboxing
- Configure environment variables

**Design**:

```ini
[Unit]
  ├─ Description and documentation
  └─ Dependency: network-online.target

[Service]
  ├─ Type: simple (foreground process)
  ├─ ExecStart: /usr/local/bin/ollama serve
  ├─ User/Group: ollama (unprivileged)
  ├─ Restart: always (resilience)
  └─ Environment variables:
      ├─ OLLAMA_HOST=127.0.0.1:11434
      ├─ OLLAMA_MODELS=/usr/share/ollama/.ollama/models
      ├─ OLLAMA_KEEP_ALIVE=5m
      └─ OLLAMA_MAX_LOADED_MODELS=2

  Security Hardening:
  ├─ NoNewPrivileges=true
  ├─ PrivateTmp=true
  ├─ ProtectSystem=strict
  ├─ ProtectHome=true
  ├─ ReadWritePaths=/usr/share/ollama (only)
  ├─ ProtectKernelTunables=true
  ├─ RestrictNamespaces=true
  ├─ SystemCallFilter=@system-service
  └─ LimitNOFILE=65536

[Install]
  └─ WantedBy: multi-user.target
```

**Rationale**:
- Systemd sandboxing provides kernel-level isolation
- Read-only filesystem prevents tampering
- System call filtering reduces attack surface
- Resource limits prevent DoS

---

## Security Architecture

### Threat Model

**Assumptions**:
- Attacker has network access to management network
- Attacker may attempt SSH brute force
- Attacker may compromise CI/CD pipeline
- Attacker may attempt local privilege escalation

**Out of Scope**:
- Physical access to GPU node
- Compromise of GitHub's infrastructure
- Zero-day exploits in Linux kernel

### Security Controls

#### Layer 1: Network Security

```
Control: Network Isolation
  ├─ Air-gap prevents outbound connections
  ├─ Firewall drops all except SSH
  └─ Ollama bound to localhost only

Control: SSH Hardening
  ├─ Key-only authentication
  ├─ No root login
  ├─ No password authentication
  └─ Limited to management network
```

#### Layer 2: Authentication & Authorization

```
Control: Service User Isolation
  ├─ Ollama runs as 'ollama' user (UID 1000+)
  ├─ No interactive shell
  ├─ No sudo privileges
  └─ Home directory: /usr/share/ollama

Control: File Permissions
  ├─ Binary: root:root, 755
  ├─ Models: ollama:ollama, 644
  ├─ Config: root:root, 644
  └─ Data directory: ollama:ollama, 750
```

#### Layer 3: System Hardening

```
Control: Systemd Sandboxing
  ├─ ProtectSystem=strict (read-only root)
  ├─ ProtectHome=true (no /home access)
  ├─ PrivateTmp=true (isolated /tmp)
  ├─ NoNewPrivileges=true (no setuid)
  └─ RestrictNamespaces=true

Control: SELinux
  ├─ Enforcing mode (if available)
  ├─ Type enforcement
  └─ Confined processes
```

#### Layer 4: Audit & Monitoring

```
Control: Audit Logging
  ├─ Ollama binary execution logged
  ├─ Model file access logged
  └─ Logs in journald (persistent)

Control: Service Monitoring
  ├─ Systemd tracks service state
  ├─ Automatic restarts on failure
  └─ Rate limiting on restart failures
```

### Attack Surface Analysis

| Surface | Exposure | Mitigation |
|---------|----------|------------|
| Network (SSH) | Management network only | Key-only auth, fail2ban (optional) |
| Ollama API | Localhost only | Not exposed externally |
| File System | Models directory | Restricted ownership, SELinux |
| Systemd | Service control | Requires sudo (deploy-user) |
| GPU | Direct access | User namespaces, cgroups |

---

## Deployment Flow

### Detailed Sequence Diagram

```
┌─────────┐          ┌──────────┐          ┌──────────┐          ┌─────────┐
│  User   │          │  GitHub  │          │    SSH   │          │   GPU   │
│         │          │ Actions  │          │  Channel │          │   Node  │
└────┬────┘          └────┬─────┘          └────┬─────┘          └────┬────┘
     │                    │                     │                      │
     │ 1. Trigger         │                     │                      │
     │ Workflow           │                     │                      │
     ├───────────────────▶│                     │                      │
     │                    │                     │                      │
     │                    │ 2. Download         │                      │
     │                    │    Ollama           │                      │
     │                    │ (github.com)        │                      │
     │                    ├─────────┐           │                      │
     │                    │         │           │                      │
     │                    │◀────────┘           │                      │
     │                    │                     │                      │
     │                    │ 3. Pull Models      │                      │
     │                    │ (ollama.com)        │                      │
     │                    ├─────────┐           │                      │
     │                    │         │           │                      │
     │                    │◀────────┘           │                      │
     │                    │                     │                      │
     │                    │ 4. Create Bundle    │                      │
     │                    ├─────────┐           │                      │
     │                    │         │           │                      │
     │                    │◀────────┘           │                      │
     │                    │                     │                      │
     │                    │ 5. Setup SSH        │                      │
     │                    ├────────────────────▶│                      │
     │                    │                     │                      │
     │                    │ 6. Transfer Bundle  │                      │
     │                    ├────────────────────▶│ 7. Receive           │
     │                    │                     ├─────────────────────▶│
     │                    │                     │                      │
     │                    │ 8. Execute Bootstrap│                      │
     │                    ├────────────────────▶│ 9. Run Scripts       │
     │                    │                     ├─────────────────────▶│
     │                    │                     │                      │
     │                    │                     │                      │ 10. Install
     │                    │                     │                      │     Ollama
     │                    │                     │                      ├─────┐
     │                    │                     │                      │     │
     │                    │                     │                      │◀────┘
     │                    │                     │                      │
     │                    │                     │                      │ 11. Load
     │                    │                     │                      │     Models
     │                    │                     │                      ├─────┐
     │                    │                     │                      │     │
     │                    │                     │                      │◀────┘
     │                    │                     │                      │
     │                    │                     │                      │ 12. Harden
     │                    │                     │                      │     System
     │                    │                     │                      ├─────┐
     │                    │                     │                      │     │
     │                    │                     │                      │◀────┘
     │                    │                     │                      │
     │                    │                     │ 13. Status OK        │
     │                    │◀────────────────────┼──────────────────────┤
     │                    │                     │                      │
     │ 14. Success        │                     │                      │
     │◀───────────────────┤                     │                      │
     │                    │                     │                      │
```

### State Transitions

```
┌─────────────┐
│   INITIAL   │ (Fresh GPU node, no Ollama)
└──────┬──────┘
       │
       │ bootstrap-gpu-node.sh executed
       ▼
┌─────────────┐
│  VERIFYING  │ (Checking bundle integrity)
└──────┬──────┘
       │
       │ Bundle valid
       ▼
┌─────────────┐
│ INSTALLING  │ (install-ollama-offline.sh)
└──────┬──────┘
       │
       │ Binary installed, user created
       ▼
┌─────────────┐
│   LOADING   │ (load-models.sh)
└──────┬──────┘
       │
       │ Models copied and indexed
       ▼
┌─────────────┐
│  HARDENING  │ (harden-node.sh)
└──────┬──────┘
       │
       │ Security controls applied
       ▼
┌─────────────┐
│   RUNNING   │ (Ollama service active, models ready)
└─────────────┘

Error states (any phase):
  │
  ├─▶ FAILED_VERIFICATION (bundle corrupt)
  ├─▶ FAILED_INSTALLATION (binary issue)
  ├─▶ FAILED_LOADING (disk full, permissions)
  └─▶ FAILED_HARDENING (config error)
```

---

## Data Flow

### Artifact Bundle Structure

```
deployment-bundle/
├── installers/
│   ├── ollama                    # Binary (30-50 MB)
│   ├── install.sh                # Unused (reference only)
│   └── checksums.txt             # SHA256 hashes
│
├── models/
│   ├── blobs/
│   │   └── sha256-<hash>         # Model weights (GB-sized)
│   ├── manifests/
│   │   └── registry.ollama.ai/
│   │       └── library/
│   │           └── codellama/
│   │               ├── 7b        # Model manifest
│   │               └── 13b
│   └── manifest.txt              # Human-readable inventory
│
├── scripts/
│   ├── bootstrap-gpu-node.sh     # Orchestrator
│   ├── install-ollama-offline.sh # Installer
│   ├── load-models.sh            # Model loader
│   ├── harden-node.sh            # Security
│   └── verify-deployment.sh      # Validator
│
├── config/
│   └── ollama.service            # Systemd unit file
│
└── deployment.json               # Metadata
    ├─ timestamp
    ├─ ollama_version
    ├─ models
    ├─ commit_sha
    └─ triggered_by
```

### Model Storage Layout

**CI/CD Runner** (`~/.ollama/models/`):
```
models/
├── blobs/
│   └── sha256-abc123...          # Model binary blob
└── manifests/
    └── registry.ollama.ai/
        └── library/
            └── codellama/
                └── 7b            # Points to blob
```

**GPU Node** (`/usr/share/ollama/.ollama/models/`):
```
models/
├── blobs/
│   └── sha256-abc123...          # Same blob, copied
└── manifests/
    └── registry.ollama.ai/
        └── library/
            └── codellama/
                └── 7b            # Same structure
```

**Key**: Ollama uses content-addressable storage. The manifest references blobs by SHA256, so copying preserves integrity.

---

## Technology Stack

### CI/CD Layer

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| CI/CD | GitHub Actions | Native integration, free for public repos |
| Artifact storage | GitHub Artifacts | Built-in, no external deps |
| Transfer | SSH/SCP | Standard, secure, firewall-friendly |
| Checksum | SHA256 | Industry standard, collision-resistant |

### Target Node Layer

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| OS | RHEL/Rocky/AlmaLinux | Enterprise stability, SELinux support |
| Init system | systemd | Modern, feature-rich, sandboxing |
| Firewall | firewalld | RHEL default, zone-based |
| Shell | Bash 4+ | Ubiquitous, robust scripting |
| Service user | ollama (unprivileged) | Least privilege |

### Application Layer

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| LLM runtime | Ollama | Offline-capable, simple API |
| Models | CodeLlama | Code generation, moderate size |
| API | REST (localhost) | Standard, language-agnostic |
| Storage | Content-addressable | Deduplication, integrity |

---

## Design Decisions

### Decision 1: Why Two-Phase Deployment?

**Options Considered**:
1. Direct download on GPU node
2. Manual file transfer
3. Two-phase CI/CD bundle

**Chosen**: Two-phase CI/CD bundle

**Rationale**:
- **Air-gap requirement**: Direct download impossible
- **Reproducibility**: Manual transfer is error-prone
- **Automation**: CI/CD ensures consistency
- **Auditability**: Bundle includes metadata

**Trade-offs**:
- Complexity: Requires CI/CD setup
- Transfer time: Large bundles (10-50 GB)

### Decision 2: Why Localhost-Only Ollama?

**Options Considered**:
1. Expose on 0.0.0.0:11434 (all interfaces)
2. Expose on private network interface
3. Localhost-only (127.0.0.1:11434)

**Chosen**: Localhost-only

**Rationale**:
- **Security**: No external exposure reduces attack surface
- **Compliance**: Satisfies air-gap requirements
- **Flexibility**: Users can tunnel via SSH if needed

**Trade-offs**:
- Accessibility: Requires SSH tunnel or reverse proxy for remote access
- Workaround: Documented in README for dev environments

### Decision 3: Why systemd Service?

**Options Considered**:
1. Manual execution (background process)
2. Init script (SysV)
3. systemd service

**Chosen**: systemd service

**Rationale**:
- **Auto-start**: Survives reboots
- **Monitoring**: systemd tracks state
- **Sandboxing**: Built-in security features
- **Logging**: Integrated with journald
- **Standard**: RHEL 8+ default

**Trade-offs**:
- None significant (systemd is standard on target OS)

### Decision 4: Why rsync for Model Transfer?

**Options Considered**:
1. `cp -r`
2. `tar` extract in place
3. `rsync`

**Chosen**: rsync

**Rationale**:
- **Progress**: Shows transfer status
- **Resume**: Can recover from interruptions
- **Verification**: Checksums built-in
- **Efficiency**: Only copies changed files (for re-deployments)

**Trade-offs**:
- Dependency: rsync must be installed (standard on RHEL)

### Decision 5: Why Pinned Ollama Version?

**Options Considered**:
1. Always latest version
2. Pinned version (0.5.4)
3. User-specified version

**Chosen**: Pinned version

**Rationale**:
- **Reproducibility**: Same deployment always uses same version
- **Testing**: Can test specific version in CI/CD
- **Stability**: Avoids breaking changes from updates

**Trade-offs**:
- Maintenance: Must manually update version number
- Workaround: Document update process in README

### Decision 6: Why Bash Instead of Python/Go?

**Options Considered**:
1. Bash scripts
2. Python application
3. Go binary

**Chosen**: Bash scripts

**Rationale**:
- **No dependencies**: Bash available on all Linux systems
- **Simplicity**: Shell commands are familiar to sysadmins
- **Transparency**: Easy to audit and modify
- **Offline-safe**: No pip install or go get required

**Trade-offs**:
- Error handling: Less sophisticated than Python
- Maintainability: Large bash scripts can be complex
- Mitigation: `set -euo pipefail`, modular scripts

---

## Future Enhancements

### 1. Multi-GPU Support

**Current**: Single GPU or CPU-only
**Proposed**:
```bash
Environment="CUDA_VISIBLE_DEVICES=0,1,2,3"
Environment="OLLAMA_NUM_PARALLEL=4"
```

**Benefits**:
- Concurrent model inference
- Higher throughput

### 2. Model Rotation

**Current**: Models loaded once, persist indefinitely
**Proposed**:
- Hot-swap models without service restart
- LRU eviction for disk space management

### 3. Monitoring Integration

**Current**: Manual `systemctl status` checks
**Proposed**:
- Prometheus metrics exporter
- Grafana dashboard
- Alerting on failures

### 4. Backup/Restore

**Current**: No automated backup
**Proposed**:
```bash
backup-ollama.sh → tarball of /usr/share/ollama
restore-ollama.sh → restore from tarball
```

### 5. Multi-Node Deployment

**Current**: Single GPU node
**Proposed**:
- Ansible playbook for fleet deployment
- Parallel deployment to N nodes
- Centralized verification reporting

### 6. Model Registry

**Current**: Models bundled in each deployment
**Proposed**:
- Shared model cache on network storage
- Nodes pull from internal registry
- Reduces bundle size

### 7. Rollback Capability

**Current**: No rollback mechanism
**Proposed**:
- Keep previous bundle in `/var/backups/`
- `rollback.sh` to revert to previous version
- Automated on deployment failure

### 8. Custom Model Support

**Current**: Pre-defined CodeLlama models
**Proposed**:
- Support for custom fine-tuned models
- GGUF file import
- Modelfile-based custom models

---

## Appendix

### Glossary

- **Air-gap**: Physical or logical separation from external networks
- **CI/CD**: Continuous Integration/Continuous Deployment
- **Idempotent**: Operation that produces same result when run multiple times
- **Systemd**: Linux init system and service manager
- **SELinux**: Security-Enhanced Linux (mandatory access control)
- **Blob**: Binary large object (model weights file)
- **Manifest**: Metadata file pointing to model blobs

### References

- Ollama Documentation: https://github.com/ollama/ollama/tree/main/docs
- GitHub Actions: https://docs.github.com/en/actions
- systemd: https://www.freedesktop.org/software/systemd/man/
- SELinux: https://www.redhat.com/en/topics/linux/what-is-selinux
- firewalld: https://firewalld.org/documentation/

### Version History

- **v1.0** (2025-11-18): Initial design for RHEL/Rocky with CodeLlama

---

**Design Document Status**: Complete
**Last Updated**: 2025-11-18
**Authors**: OpenCode Development Team
