# VPS-1 to VPS-4 DevNet/TestNet Migration Report

## Migration Overview

**Date:** 2025-12-17
**Source:** VPS-1 (72.60.210.201)
**Destination:** VPS-4 (217.196.51.190:2222)
**Purpose:** Migrate development files and components to designated DevNet/TestNet environment

---

## Migration Summary

### Phase 1: Prerequisites Setup
- Installed Git v2.47.3 on VPS-4
- Installed Node.js v22.21.0 and npm 10.9.4 on VPS-4
- Created backup: `/root/vps4-sugxcoin-backup-20251217-110329.tar.gz`

### Phase 2: Source Code Migration
| Repository | Files Synced | Size |
|------------|--------------|------|
| gx-coin-fabric | 4,396 | ~1.2GB |
| gx-protocol-backend | 37,685 | ~738MB |
| gx-wallet-frontend | 39,955 | ~877MB |
| gx-admin-frontend | 51,319 | ~903MB |
| gx-infra-arch | 125 | ~1.1MB |
| docs | 3 | ~16KB |
| **Total** | **133,483** | **3.7GB** |

### Phase 3: Environment Configuration
- Verified all Git repositories accessible
- Fixed Git safe.directory configurations
- Synced all environment files (.env, .env.local, .env.development)
- Synced .kube configuration

### Phase 4: Docker Images Migration
| Image | Tag | Size |
|-------|-----|------|
| gx-protocol/svc-admin | 2.1.0 | 1.34GB |
| gx-protocol/svc-governance | 2.1.0 | 1.05GB |
| gx-protocol/svc-identity | 2.1.0 | 1.59GB |
| gx-protocol/svc-loanpool | 2.1.0 | 1.05GB |
| gx-protocol/svc-organization | 2.1.0 | 1.05GB |
| gx-protocol/svc-tax | 2.1.0 | 1.57GB |
| gx-protocol/svc-tokenomics | 2.1.0 | 1.34GB |
| gx-protocol/outbox-submitter | 2.1.0 | 1.34GB |
| gx-protocol/projector | 2.1.0 | 1.34GB |

- Exported 3.2GB compressed archive
- Transfer speed: ~7-10 MB/s average
- Successfully imported all 9 images

### Phase 5: Verification
- All file counts verified
- All Git repositories accessible with correct remotes
- All Docker images loaded and verified
- Kubernetes nodes: 2 of 4 Ready
- DevNet/TestNet namespaces present

---

## VPS-4 Final State

### System
- Hostname: srv1089624.hstgr.cloud
- OS: AlmaLinux 10 (Purple Lion)
- CPU: 8 vCPU
- Memory: 32GB (26GB available)
- Disk: 399GB total, 284GB available

### Software
- Git: 2.47.3
- Node.js: 22.21.0
- npm: 10.9.4
- Docker: 28.5.1
- K3s: v1.33.5+k3s1

### Kubernetes Namespaces
- backend-devnet (Active)
- backend-testnet (Active)
- fabric-devnet (Active)
- fabric-testnet (Active)

---

## Post-Migration Tasks (Recommended)

1. **Environment Configuration**
   - Review and update .env files for DevNet/TestNet specific values
   - Update API endpoints if needed
   - Configure DevNet/TestNet database connections

2. **Kubernetes**
   - Investigate NotReady nodes (srv1092158, srv1117946)
   - Clean up Terminating pods
   - Deploy DevNet/TestNet workloads

3. **Testing**
   - Run npm install in frontend repos if needed
   - Test local development builds
   - Verify Fabric network connectivity

---

## Challenges and Solutions

| Challenge | Solution |
|-----------|----------|
| VPS-4 SSH on non-standard port | Used port 2222 for all SSH/rsync operations |
| Git "dubious ownership" errors | Added directories to git safe.directory |
| Large Docker image transfer | Used compressed tar archive (3.2GB vs 15GB uncompressed) |
| Network latency (208ms) | rsync with resume capability handled interruptions |

---

## Access Information

| Server | IP | SSH Port | Purpose |
|--------|-----|----------|---------|
| VPS-1 | 72.60.210.201 | 22 | Production |
| VPS-4 | 217.196.51.190 | 2222 | DevNet/TestNet |

---

**Migration Status:** COMPLETED
**Migration Duration:** ~45 minutes
**Total Data Transferred:** ~7GB (source + Docker images)
