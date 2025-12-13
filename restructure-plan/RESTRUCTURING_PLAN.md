# GX Coin Protocol Infrastructure Restructuring Plan

**Document Version:** 1.0
**Created:** December 13, 2025
**Status:** PENDING APPROVAL

---

## Overview

This document outlines the comprehensive restructuring plan to align the GX Coin Protocol infrastructure with the intended architecture design, industry best practices, and high-availability requirements.

### Goals

1. **Environment Isolation** - Separate DevNet/TestNet from MainNet
2. **High Availability** - Proper 3-node MainNet cluster with fault tolerance
3. **Data Protection** - Comprehensive backup coverage for all servers
4. **Security Hardening** - Implement security best practices
5. **Resource Optimization** - Clean up unused resources and optimize allocation
6. **Operational Excellence** - Proper monitoring, alerting, and documentation

---

## Target Architecture

### Server Role Assignment

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GX COIN PROTOCOL INFRASTRUCTURE                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  VPS-1 (195.35.36.174) - LOW-SPEC - STANDALONE                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  Website Server                                                  │     │
│  │  ├── gxcoin.money (Marketing Website)                           │     │
│  │  └── Partner Simulator (gx-partnerorg1)                         │     │
│  │      └── Simulated Partner Validator Node                       │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  VPS-2 (217.196.51.190) - HIGH-SPEC - STANDALONE                        │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  Development Environment                                         │     │
│  │  ├── DevNet (fabric-devnet namespace)                           │     │
│  │  │   └── Single-node Fabric for development                     │     │
│  │  ├── TestNet (fabric-testnet namespace)                         │     │
│  │  │   └── 3-orderer, 2-peer Fabric network                       │     │
│  │  ├── Backend DevNet (backend-devnet namespace)                  │     │
│  │  ├── Backend TestNet (backend-testnet namespace)                │     │
│  │  ├── Monitoring (development metrics)                           │     │
│  │  └── Docker Registry (dev images)                               │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  VPS-3, VPS-4, VPS-5 - HIGH-SPEC - MAINNET HA CLUSTER                   │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  MainNet Production Cluster (3-node K3s HA)                     │     │
│  │                                                                  │     │
│  │  VPS-3 (72.60.210.201) - Control-Plane + Workload               │     │
│  │  ├── orderer0, orderer3                                         │     │
│  │  ├── peer0-org1                                                 │     │
│  │  ├── Backend services (svc-*)                                   │     │
│  │  └── Monitoring (Grafana, Prometheus)                           │     │
│  │                                                                  │     │
│  │  VPS-4 (72.61.116.210) - Control-Plane + Workload               │     │
│  │  ├── orderer1, orderer4                                         │     │
│  │  ├── peer0-org2                                                 │     │
│  │  ├── PostgreSQL, Redis replicas                                 │     │
│  │  └── Certificate Authorities                                    │     │
│  │                                                                  │     │
│  │  VPS-5 (72.61.81.3) - Control-Plane + Workload                  │     │
│  │  ├── orderer2                                                   │     │
│  │  ├── peer1-org1, peer1-org2                                     │     │
│  │  ├── PostgreSQL, Redis replicas                                 │     │
│  │  └── Ingress Controller                                         │     │
│  │                                                                  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  BACKUP DESTINATION                                                      │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  Google Drive (via rclone)                                       │     │
│  │  ├── /gx-backups/vps1-website/                                  │     │
│  │  ├── /gx-backups/vps2-devtest/                                  │     │
│  │  └── /gx-backups/mainnet/                                       │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Emergency Stabilization (Day 1-2)

### 1.1 Clean VPS-3 Disk Space

**Priority:** CRITICAL
**Risk Level:** Medium (potential service restart needed)
**Estimated Time:** 1-2 hours

**Actions:**
```bash
# On VPS-3 (72.60.210.201)

# 1. Prune Docker build cache (recovers ~70GB)
docker builder prune -a -f

# 2. Remove unused Docker images
docker image prune -a -f

# 3. Remove unused volumes
docker volume prune -f

# 4. Verify space recovered
df -h /
```

**Expected Outcome:** Disk usage reduced from 79% to ~35%

### 1.2 Stop Duplicate Docker Compose Fabric

**Priority:** CRITICAL
**Risk Level:** High (requires coordination with team)
**Estimated Time:** 2-4 hours

**Pre-requisites:**
- Confirm which Fabric network is the authoritative source
- Backup any unique data from Docker Compose network
- Schedule maintenance window

**Actions:**
```bash
# On VPS-3 (72.60.210.201)

# 1. Identify the docker-compose file location
find / -name "docker-compose*.yaml" -o -name "docker-compose*.yml" 2>/dev/null

# 2. Backup the compose configuration
cp /path/to/docker-compose.yaml /root/backup-docker-compose.yaml

# 3. Stop the Docker Compose network
cd /path/to/compose/directory
docker-compose down

# 4. Verify containers stopped
docker ps

# 5. Optionally remove the volumes (AFTER confirming K8s Fabric has all data)
# docker-compose down -v  # DESTRUCTIVE - removes data
```

**Expected Outcome:**
- 17 containers stopped
- Port conflicts resolved
- Resource contention eliminated
- Single authoritative Fabric network (Kubernetes)

### 1.3 Investigate and Fix Backend Service Health

**Priority:** HIGH
**Risk Level:** Low
**Estimated Time:** 2-4 hours

**Actions:**
```bash
# Check logs for failing pods
kubectl logs -n backend-mainnet -l app=svc-tokenomics --tail=100
kubectl logs -n backend-mainnet -l app=svc-governance --tail=100

# Check events
kubectl get events -n backend-mainnet --sort-by='.lastTimestamp'

# Describe failing pods
kubectl describe pod -n backend-mainnet -l app=svc-tokenomics

# Restart deployments if needed
kubectl rollout restart deployment -n backend-mainnet svc-tokenomics
kubectl rollout restart deployment -n backend-mainnet svc-governance

# Check outbox-submitter
kubectl logs -n backend-mainnet -l app=outbox-submitter --tail=200
```

**Expected Outcome:** All backend services running at 3/3 replicas

---

## Phase 2: Security Hardening (Day 3-5)

### 2.1 SSH Key Authentication

**Priority:** HIGH
**Risk Level:** Medium (potential lockout if misconfigured)
**Estimated Time:** 2-3 hours

**Actions for each server:**
```bash
# Generate SSH key pair (on your local machine)
ssh-keygen -t ed25519 -C "gx-admin@gxcoin.money" -f ~/.ssh/gx-admin

# Copy public key to each server
ssh-copy-id -i ~/.ssh/gx-admin.pub root@195.35.36.174
ssh-copy-id -i ~/.ssh/gx-admin.pub root@217.196.51.190
ssh-copy-id -i ~/.ssh/gx-admin.pub root@72.60.210.201
ssh-copy-id -i ~/.ssh/gx-admin.pub root@72.61.116.210
ssh-copy-id -i ~/.ssh/gx-admin.pub root@72.61.81.3

# Test key-based login works BEFORE disabling password auth
ssh -i ~/.ssh/gx-admin root@<each-ip>

# On each server, modify SSH config
vim /etc/ssh/sshd_config
# Set: PasswordAuthentication no
# Set: PubkeyAuthentication yes
# Set: PermitRootLogin prohibit-password

# Restart SSH
systemctl restart sshd
```

### 2.2 Disable Unnecessary Services

**Priority:** MEDIUM
**Risk Level:** Low
**Estimated Time:** 1 hour

**Actions:**
```bash
# On VPS-2, VPS-3, VPS-5 (not VPS-1 which needs Apache for reverse proxy)
systemctl stop httpd
systemctl disable httpd

# On all servers - disable rpcbind if not needed
systemctl stop rpcbind
systemctl disable rpcbind
```

### 2.3 Firewall Hardening

**Priority:** MEDIUM
**Risk Level:** Medium
**Estimated Time:** 2-3 hours

**Actions:**
```bash
# On each server - verify firewalld is active
systemctl status firewalld

# Create zone for internal K3s communication
firewall-cmd --permanent --new-zone=k3s-cluster
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.60.210.201
firewall-cmd --permanent --zone=k3s-cluster --add-source=217.196.51.190
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.61.116.210
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.61.81.3

# Allow K3s ports only from cluster members
firewall-cmd --permanent --zone=k3s-cluster --add-port=6443/tcp
firewall-cmd --permanent --zone=k3s-cluster --add-port=2379-2380/tcp
firewall-cmd --permanent --zone=k3s-cluster --add-port=10250/tcp
firewall-cmd --permanent --zone=k3s-cluster --add-port=10251/tcp
firewall-cmd --permanent --zone=k3s-cluster --add-port=10252/tcp

firewall-cmd --reload
```

---

## Phase 3: Architecture Restructuring (Day 6-14)

### 3.1 Migrate TestNet to VPS-2

**Priority:** HIGH
**Risk Level:** High (requires careful planning)
**Estimated Time:** 8-16 hours

**Approach Options:**

**Option A: Fresh TestNet Installation (Recommended)**
- Create new K3s standalone cluster on VPS-2
- Deploy fresh TestNet Fabric network
- Deploy fresh TestNet backend services
- No data migration (TestNet data is disposable)

**Option B: Migrate Existing TestNet**
- Backup TestNet data from VPS-4
- Remove VPS-4 from current cluster
- Set up VPS-2 as standalone
- Restore TestNet data to VPS-2

**Recommended: Option A**

**Actions:**
```bash
# On VPS-2 (217.196.51.190)

# 1. Leave the existing cluster (if still joined)
kubectl drain srv1089624.hstgr.cloud --ignore-daemonsets --delete-emptydir-data
# From another control-plane:
kubectl delete node srv1089624.hstgr.cloud

# 2. Uninstall K3s
/usr/local/bin/k3s-uninstall.sh

# 3. Install fresh K3s standalone
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init=false \
  --disable traefik

# 4. Deploy DevNet namespace
kubectl create namespace fabric-devnet
kubectl create namespace backend-devnet

# 5. Deploy TestNet namespace
kubectl create namespace fabric-testnet
kubectl create namespace backend-testnet

# 6. Deploy Fabric TestNet (simplified network)
# [Apply TestNet manifests]

# 7. Deploy Backend TestNet services
# [Apply Backend manifests]
```

### 3.2 Restructure MainNet Cluster (VPS-3, VPS-4, VPS-5)

**Priority:** HIGH
**Risk Level:** HIGH (production impact)
**Estimated Time:** 16-24 hours (with maintenance window)

**Current State:**
- VPS-3: Control-plane
- VPS-4: Worker (needs promotion)
- VPS-5: Control-plane

**Target State:**
- VPS-3: Control-plane + Workload
- VPS-4: Control-plane + Workload
- VPS-5: Control-plane + Workload

**Actions:**
```bash
# 1. Remove TestNet components from current cluster
kubectl delete namespace fabric-testnet
kubectl delete namespace backend-testnet

# 2. Promote VPS-4 to control-plane
# This requires removing and re-adding the node

# On VPS-4:
# Stop K3s agent
systemctl stop k3s-agent
/usr/local/bin/k3s-agent-uninstall.sh

# Get join token from existing control-plane (VPS-3)
cat /var/lib/rancher/k3s/server/node-token

# Re-join as server (control-plane)
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> sh -s - server \
  --server https://72.60.210.201:6443

# 3. Verify 3-node control-plane
kubectl get nodes
# All should show: control-plane,etcd,master

# 4. Redistribute workloads across all 3 nodes
kubectl label node srv1117946.hstgr.cloud node-role.kubernetes.io/mainnet=true
kubectl label node srv1089618.hstgr.cloud node-role.kubernetes.io/mainnet=true
kubectl label node srv1092158.hstgr.cloud node-role.kubernetes.io/mainnet=true
```

### 3.3 Rebalance Fabric Components

**Priority:** MEDIUM
**Risk Level:** Medium
**Estimated Time:** 4-8 hours

**Target Distribution:**

| Component | VPS-3 | VPS-4 | VPS-5 |
|-----------|-------|-------|-------|
| orderer0 | X | | |
| orderer1 | | X | |
| orderer2 | | | X |
| orderer3 | X | | |
| orderer4 | | X | |
| peer0-org1 | X | | |
| peer1-org1 | | | X |
| peer0-org2 | | X | |
| peer1-org2 | | | X |
| ca-root | | | X |
| ca-tls | X | | |
| ca-orderer | | X | |
| ca-org1 | X | | |
| ca-org2 | | | X |

**Actions:**
```bash
# Use node affinity in deployments/statefulsets
# Example for orderer0:
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - srv1089618.hstgr.cloud

# Rollout changes
kubectl rollout restart statefulset -n fabric
```

---

## Phase 4: Backup Implementation (Day 7-10)

### 4.1 Install rclone on All Servers

**Priority:** HIGH
**Risk Level:** Low
**Estimated Time:** 1-2 hours

**Actions on each server:**
```bash
# Install rclone
curl https://rclone.org/install.sh | bash

# Configure Google Drive remote (interactive)
rclone config

# Configuration steps:
# n) New remote
# name: gdrive-backup
# Storage: Google Drive
# [Follow OAuth flow]

# Verify connection
rclone lsd gdrive-backup:
```

### 4.2 Create Backup Scripts

**Priority:** HIGH
**Risk Level:** Low
**Estimated Time:** 2-3 hours

**VPS-1 Backup Script:**
```bash
#!/bin/bash
# /root/scripts/backup-vps1.sh

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup-${BACKUP_DATE}"
REMOTE="gdrive-backup:gx-backups/vps1-website"

mkdir -p ${BACKUP_DIR}

# Backup website files
tar -czf ${BACKUP_DIR}/website.tar.gz /var/www/gxcoin.money

# Backup K3s manifests
kubectl get all -A -o yaml > ${BACKUP_DIR}/k8s-all.yaml

# Backup partner simulator PVCs
kubectl get pvc -n gx-partnerorg1 -o yaml > ${BACKUP_DIR}/pvcs.yaml

# Upload to Google Drive
rclone copy ${BACKUP_DIR} ${REMOTE}/${BACKUP_DATE}/ --progress

# Cleanup
rm -rf ${BACKUP_DIR}

# Retention: Keep last 30 days
rclone delete ${REMOTE} --min-age 30d
```

**MainNet Backup Script (runs from VPS-3):**
```bash
#!/bin/bash
# /root/scripts/backup-mainnet.sh

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup-mainnet-${BACKUP_DATE}"
REMOTE="gdrive-backup:gx-backups/mainnet"

mkdir -p ${BACKUP_DIR}

# Backup Fabric crypto materials
kubectl cp fabric/ca-root-0:/var/hyperledger ${BACKUP_DIR}/ca-root/
kubectl cp fabric/ca-org1-0:/var/hyperledger ${BACKUP_DIR}/ca-org1/
kubectl cp fabric/ca-org2-0:/var/hyperledger ${BACKUP_DIR}/ca-org2/

# Backup PostgreSQL (already has CronJob, but add off-site)
kubectl exec -n backend-mainnet postgres-0 -- pg_dumpall -U postgres > ${BACKUP_DIR}/postgres.sql

# Backup K3s state
cp -r /var/lib/rancher/k3s/server/db ${BACKUP_DIR}/etcd-snapshot/

# Backup all manifests
kubectl get all -A -o yaml > ${BACKUP_DIR}/k8s-all.yaml

# Upload
rclone copy ${BACKUP_DIR} ${REMOTE}/${BACKUP_DATE}/ --progress

# Cleanup
rm -rf ${BACKUP_DIR}

# Retention
rclone delete ${REMOTE} --min-age 30d
```

### 4.3 Schedule Backup Jobs

**Actions:**
```bash
# On each server, add to crontab
crontab -e

# VPS-1 (daily at 2 AM)
0 2 * * * /root/scripts/backup-vps1.sh >> /var/log/backup.log 2>&1

# VPS-2 (daily at 3 AM)
0 3 * * * /root/scripts/backup-vps2.sh >> /var/log/backup.log 2>&1

# VPS-3 (MainNet primary backup at 4 AM)
0 4 * * * /root/scripts/backup-mainnet.sh >> /var/log/backup.log 2>&1
```

---

## Phase 5: Monitoring Enhancement (Day 11-14)

### 5.1 Add Fabric Metrics Exporter

**Actions:**
```yaml
# Deploy Fabric operations metrics scraping
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fabric-peers
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: peer
  namespaceSelector:
    matchNames:
    - fabric
  endpoints:
  - port: operations
    path: /metrics
    interval: 30s
```

### 5.2 Create Grafana Dashboards

- Fabric Network Overview
- Peer Performance
- Orderer Metrics
- Backend Service Health
- Database Metrics
- Resource Utilization per Node

### 5.3 Configure Alerting

**Critical Alerts:**
- Disk usage > 80%
- Pod CrashLoopBackOff
- Certificate expiry < 30 days
- Orderer/Peer down
- Database connection failures
- Backup job failures

---

## Implementation Schedule

| Phase | Task | Duration | Dependencies |
|-------|------|----------|--------------|
| 1.1 | Clean VPS-3 Disk | 2 hours | None |
| 1.2 | Stop Docker Compose Fabric | 4 hours | Phase 1.1 |
| 1.3 | Fix Backend Services | 4 hours | Phase 1.2 |
| 2.1 | SSH Key Authentication | 3 hours | None |
| 2.2 | Disable Unnecessary Services | 1 hour | None |
| 2.3 | Firewall Hardening | 3 hours | Phase 2.1 |
| 3.1 | Migrate TestNet to VPS-2 | 16 hours | Phase 1 |
| 3.2 | Restructure MainNet Cluster | 24 hours | Phase 3.1 |
| 3.3 | Rebalance Fabric Components | 8 hours | Phase 3.2 |
| 4.1 | Install rclone | 2 hours | None |
| 4.2 | Create Backup Scripts | 3 hours | Phase 4.1 |
| 4.3 | Schedule Backup Jobs | 1 hour | Phase 4.2 |
| 5.1 | Fabric Metrics Exporter | 4 hours | Phase 3.3 |
| 5.2 | Grafana Dashboards | 8 hours | Phase 5.1 |
| 5.3 | Configure Alerting | 4 hours | Phase 5.2 |

**Total Estimated Duration:** 12-14 working days

---

## Risk Mitigation

### Phase 1 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Docker prune removes needed images | Medium | Document running containers before prune |
| Stopping wrong Fabric network | Critical | Verify which network is authoritative |
| Service downtime during fixes | Medium | Schedule maintenance window |

### Phase 3 Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data loss during migration | Critical | Full backup before any changes |
| Extended MainNet downtime | Critical | Detailed rollback plan |
| etcd quorum loss | Critical | Never remove 2 nodes simultaneously |

### Rollback Procedures

**Phase 1 Rollback:**
```bash
# If Docker Compose network needs to restart
cd /path/to/compose
docker-compose up -d
```

**Phase 3 Rollback:**
```bash
# Restore etcd from snapshot
k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot
```

---

## Success Criteria

### Phase 1 Complete When:
- [ ] VPS-3 disk usage < 50%
- [ ] Single Fabric network running (Kubernetes)
- [ ] All backend services showing Ready status

### Phase 2 Complete When:
- [ ] SSH key authentication working on all servers
- [ ] Password authentication disabled
- [ ] Apache HTTPD stopped on VPS-2, VPS-3, VPS-5
- [ ] Firewall rules implemented

### Phase 3 Complete When:
- [ ] VPS-2 running standalone DevNet/TestNet
- [ ] VPS-3, VPS-4, VPS-5 as 3-node MainNet cluster
- [ ] All three nodes showing control-plane role
- [ ] Fabric components distributed across all nodes

### Phase 4 Complete When:
- [ ] rclone configured on all 5 servers
- [ ] Backup scripts tested and verified
- [ ] Automated backup jobs running
- [ ] Test restore completed successfully

### Phase 5 Complete When:
- [ ] Fabric metrics visible in Prometheus
- [ ] Grafana dashboards created
- [ ] Critical alerts configured and tested
- [ ] Runbook documented

---

## Approval

This restructuring plan requires approval before implementation begins.

**Requested Approvals:**

- [ ] Technical Lead Approval
- [ ] Operations Team Approval
- [ ] Stakeholder Acknowledgment of Maintenance Windows

**Notes:**
- Phase 1 can begin immediately (emergency stabilization)
- Phases 2-5 should wait for formal approval
- Maintenance windows should be scheduled in advance
- All changes should be documented in the work record

---

*End of Restructuring Plan*
