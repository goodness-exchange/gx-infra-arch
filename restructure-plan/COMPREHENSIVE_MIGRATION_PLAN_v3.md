# GX Blockchain Enterprise Infrastructure Migration Plan
## Comprehensive Unified Edition v3.0

**Document Version:** 3.0
**Created:** December 13, 2025
**Classification:** CONFIDENTIAL - Internal Use Only
**Project:** GX Coin Enterprise Blockchain Platform
**Domains:** goodness.exchange | gxcoin.money | wallet.gxcoin.money

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Target Architecture](#3-target-architecture)
4. [Industry Best Practices Framework](#4-industry-best-practices-framework)
5. [Certificate Authority Architecture](#5-certificate-authority-architecture)
6. [Phase 0: Emergency Stabilization](#6-phase-0-emergency-stabilization)
7. [Phase 1: Pre-Migration Preparation](#7-phase-1-pre-migration-preparation)
8. [Phase 2: Security Hardening](#8-phase-2-security-hardening)
9. [Phase 3: Infrastructure Setup](#9-phase-3-infrastructure-setup)
10. [Phase 4: Architecture Restructuring](#10-phase-4-architecture-restructuring)
11. [Phase 5: Backup Implementation](#11-phase-5-backup-implementation)
12. [Phase 6: Testing & Validation](#12-phase-6-testing--validation)
13. [Phase 7: Monitoring & Operations](#13-phase-7-monitoring--operations)
14. [Cloudflare Integration](#14-cloudflare-integration)
15. [Operational Runbooks](#15-operational-runbooks)
16. [Appendices](#16-appendices)

---

## 1. Executive Summary

### 1.1 Document Purpose

This comprehensive document consolidates findings from two independent infrastructure audits (December 11 and 13, 2025) into a unified migration plan. It addresses:

- **Emergency Stabilization** - Critical issues requiring immediate action
- **High Availability (HA)** - Eliminate single points of failure
- **Load Distribution** - Balance workloads across servers
- **Environment Separation** - MainNet, TestNet, DevNet isolation
- **Security Hardening** - Certificate management, secrets, network policies
- **Disaster Recovery** - Automated backups to Google Drive
- **Comprehensive Testing** - End-to-end validation framework

### 1.2 Critical Findings from Latest Audit (Dec 13, 2025)

| Finding | Severity | Location | Impact |
|---------|----------|----------|--------|
| **Duplicate Fabric Networks** | CRITICAL | VPS-3 (72.60.210.201) | Docker Compose AND K8s running simultaneously |
| **Disk Space Critical** | CRITICAL | VPS-3 (72.60.210.201) | 79% used, 70GB reclaimable Docker cache |
| **Backend Services Degraded** | HIGH | MainNet Cluster | svc-tokenomics 0/3, multiple services 1/3 |
| **Outbox-submitter Crashes** | HIGH | Both Nets | MainNet: 140, TestNet: 1353 restarts |
| **Missing Backups** | HIGH | All Servers | No rclone, no off-site backup coverage |
| **Architecture Mismatch** | HIGH | Cluster | TestNet on VPS-4, not VPS-2 as intended |

### 1.3 Infrastructure Inventory

| VPS | IP Address | Hostname | Specs | Current State | Target State |
|-----|------------|----------|-------|---------------|--------------|
| VPS-1 | 72.60.210.201 | srv1089618.hstgr.cloud | 8 vCPU / 32GB / 400GB | DUPLICATE Fabric + Backend | MainNet Node 1 + Monitoring |
| VPS-2 | 72.61.116.210 | srv1117946.hstgr.cloud | 8 vCPU / 32GB / 400GB | K3s Worker + TestNet | MainNet Node 2 |
| VPS-3 | 72.61.81.3 | srv1092158.hstgr.cloud | 8 vCPU / 32GB / 400GB | K3s Control-plane (NO DOCKER!) | MainNet Node 3 + Backup |
| VPS-4 | 217.196.51.190 | srv1089624.hstgr.cloud | 8 vCPU / 32GB / 400GB | K3s Control-plane (mixed) | DevNet + TestNet (standalone) |
| VPS-5 | 195.35.36.174 | srv711725.hstgr.cloud | 2 vCPU / 8GB / 100GB | Website + Partner | Website + Partner (No change) |

---

## 2. Current State Analysis

### 2.1 VPS-1 Critical Issue: Duplicate Fabric Networks

**Location:** VPS-1 (72.60.210.201)

**Docker Compose Network (17 containers running):**
```
Orderers (5):
├── orderer0.ordererorg.prod.goodness.exchange (port 27050)
├── orderer1.ordererorg.prod.goodness.exchange (port 28050)
├── orderer2.ordererorg.prod.goodness.exchange (port 29050)
├── orderer3.ordererorg.prod.goodness.exchange (port 30050)
└── orderer4.ordererorg.prod.goodness.exchange (port 31050)

Peers (4):
├── peer0.org1.prod.goodness.exchange (port 7051)
├── peer1.org1.prod.goodness.exchange (port 8051)
├── peer0.org2.prod.goodness.exchange (port 9051)
└── peer1.org2.prod.goodness.exchange (port 10051)

CouchDB (4): couchdb0-3 (ports 5984, 6984, 7984, 8984)
Chaincode (3): dev-peer chaincode containers
CA DB (1): postgres.ca (port 5433)
```

**Kubernetes Network (fabric namespace) - ALSO Running:**
```
Orderers: orderer0-0, orderer3-0
Peers: peer0-org1-0
CouchDB: couchdb-peer1-org1-0
Chaincode: gxtv3-chaincode-0
```

**RESOLUTION REQUIRED:** Determine authoritative network and stop the other.

### 2.2 Current Kubernetes Cluster Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CURRENT CLUSTER TOPOLOGY                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   4-NODE K3S CLUSTER (VPS-1, VPS-2, VPS-3, VPS-4)                           │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │                                                                     │    │
│   │  VPS-1 (72.60.210.201) - control-plane, etcd, master               │    │
│   │  VPS-4 (217.196.51.190) - control-plane, etcd, master              │    │
│   │  VPS-3 (72.61.81.3) - control-plane, etcd, master                  │    │
│   │  VPS-2 (72.61.116.210) - worker                                     │    │
│   │                                                                     │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   NAMESPACES:                                                                │
│   ├── fabric (MainNet) - distributed across VPS-1, 3, 4                     │
│   ├── fabric-testnet (TestNet) - ALL on VPS-2                               │
│   ├── backend-mainnet - distributed across cluster                          │
│   ├── backend-testnet - ALL on VPS-2                                        │
│   ├── monitoring (Grafana, Prometheus, Loki)                                │
│   ├── cert-manager                                                          │
│   ├── ingress-nginx                                                         │
│   ├── metallb-system                                                        │
│   └── registry                                                              │
│                                                                              │
│   VPS-5 (195.35.36.174) - STANDALONE K3S                                    │
│   ├── gx-partnerorg1 namespace (Partner Simulator)                          │
│   └── Website via Docker (gx-marketing-site)                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Backend Services Health Status

| Service | Desired | Ready | Status | Notes |
|---------|---------|-------|--------|-------|
| svc-admin | 3 | 3 | ✅ Healthy | |
| svc-identity | 3 | 3 | ✅ Healthy | |
| svc-governance | 3 | 1 | ⚠️ Degraded | 2 pods not ready |
| svc-loanpool | 3 | 1 | ⚠️ Degraded | 2 pods not ready |
| svc-organization | 3 | 1 | ⚠️ Degraded | 2 pods not ready |
| svc-tax | 3 | 1 | ⚠️ Degraded | 2 pods not ready |
| svc-tokenomics | 3 | 0 | ❌ Failed | ALL pods not ready |
| outbox-submitter (mainnet) | 1 | 1 | ⚠️ Warning | 140 restarts in 2d |
| outbox-submitter (testnet) | 1 | 1 | ❌ Critical | 1353 restarts in 19d |

### 2.4 Disk Space Analysis

| Server | Total | Used | Available | % Used | Status | Reclaimable |
|--------|-------|------|-----------|--------|--------|-------------|
| VPS-1 | 400GB | 312GB | 88GB | **79%** | ❌ Critical | **71.5GB** |
| VPS-2 | 400GB | 75GB | 325GB | 19% | ✅ Healthy | 0 |
| VPS-3 | 400GB | 205GB | 195GB | 52% | ✅ Healthy | 0 |
| VPS-4 | 400GB | 234GB | 166GB | 59% | ⚠️ Warning | 1.1GB |
| VPS-5 | 100GB | 14GB | 86GB | 14% | ✅ Healthy | 5.3GB |

---

## 3. Target Architecture

### 3.1 Server Role Distribution

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TARGET SERVER DISTRIBUTION                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   VPS-1 (72.60.210.201) - MAINNET PRIMARY                                   │
│   ├── Orderer 0, 3 (Raft cluster)                                          │
│   ├── Peer0.Org1                                                            │
│   ├── CouchDB (for Org1 peer)                                              │
│   ├── CA-Org1, CA-TLS                                                       │
│   ├── Backend Services (svc-identity, svc-admin, etc.)                     │
│   ├── Prometheus, Grafana, AlertManager, Loki                              │
│   └── Ingress Controller                                                    │
│                                                                              │
│   VPS-2 (72.61.116.210) - MAINNET SECONDARY                                 │
│   ├── Orderer 1, 4 (Raft cluster)                                          │
│   ├── Peer0.Org2                                                            │
│   ├── CouchDB (for Org2 peer)                                              │
│   ├── CA-Org2, CA-Orderer                                                   │
│   ├── PostgreSQL Replica                                                    │
│   ├── Redis Replica                                                         │
│   └── Backend Services Replica                                              │
│                                                                              │
│   VPS-3 (72.61.81.3) - MAINNET TERTIARY + BACKUP                           │
│   ├── Orderer 2 (Raft cluster - tiebreaker)                                │
│   ├── Peer1.Org1, Peer1.Org2                                               │
│   ├── CouchDB × 2                                                           │
│   ├── CA-Root (offline after initial setup)                                │
│   ├── PostgreSQL Primary                                                    │
│   ├── Redis Primary                                                         │
│   ├── Velero (K8s backup)                                                  │
│   └── REQUIRES: Docker installation                                         │
│                                                                              │
│   VPS-4 (217.196.51.190) - STANDALONE (DEVELOPMENT)                         │
│   ├── DevNet (fabric-devnet namespace)                                      │
│   │   └── Solo orderer, 1 peer, 1 CA, 1 CouchDB                            │
│   ├── TestNet (fabric-testnet namespace)                                    │
│   │   └── 3 orderers, 2 peers, full backend                                │
│   ├── Backend DevNet (backend-devnet namespace)                             │
│   ├── Backend TestNet (backend-testnet namespace)                           │
│   ├── Private Registry (:30500)                                             │
│   └── Development Monitoring                                                │
│                                                                              │
│   VPS-5 (195.35.36.174) - STANDALONE (NO CHANGES)                           │
│   ├── Marketing Website (gxcoin.money)                                      │
│   ├── Partner Simulator (gx-partnerorg1 namespace)                          │
│   │   └── Simulated Partner Peer for external validation testing            │
│   └── Apache HTTPD (reverse proxy)                                          │
│                                                                              │
│   BACKUP DESTINATION                                                         │
│   └── Google Drive (via rclone) - gxc@handsforeducation.org                │
│       ├── /GX-Backups/vps5-website/                                        │
│       ├── /GX-Backups/vps4-devtest/                                        │
│       ├── /GX-Backups/mainnet/daily/                                       │
│       ├── /GX-Backups/mainnet/weekly/                                      │
│       └── /GX-Backups/pre-migration/                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Kubernetes Node Labels (Target)

```bash
# VPS-1 (72.60.210.201)
kubectl label node srv1089618.hstgr.cloud \
  topology.gx.io/zone=zone-a \
  node.gx.io/role=mainnet-primary \
  fabric.gx.io/org=org1

# VPS-2 (72.61.116.210)
kubectl label node srv1117946.hstgr.cloud \
  topology.gx.io/zone=zone-b \
  node.gx.io/role=mainnet-secondary \
  fabric.gx.io/org=org2

# VPS-3 (72.61.81.3)
kubectl label node srv1092158.hstgr.cloud \
  topology.gx.io/zone=zone-c \
  node.gx.io/role=mainnet-tertiary \
  fabric.gx.io/role=backup
```

### 3.3 Fabric Component Target Distribution

| Component | VPS-1 | VPS-2 | VPS-3 |
|-----------|:-----:|:-----:|:-----:|
| orderer0 | ✓ | | |
| orderer1 | | ✓ | |
| orderer2 | | | ✓ |
| orderer3 | ✓ | | |
| orderer4 | | ✓ | |
| peer0-org1 | ✓ | | |
| peer1-org1 | | | ✓ |
| peer0-org2 | | ✓ | |
| peer1-org2 | | | ✓ |
| ca-root | | | ✓ |
| ca-tls | ✓ | | |
| ca-orderer | | ✓ | |
| ca-org1 | ✓ | | |
| ca-org2 | | | ✓ |

---

## 4. Industry Best Practices Framework

### 4.1 Hyperledger Fabric Best Practices

| Practice | Current Status | Target | Priority |
|----------|----------------|--------|----------|
| Orderer Distribution | ❌ Mostly on 1 node | Distribute across 3 nodes | 🔴 Critical |
| Peer Distribution | ❌ Unbalanced | 1+ peer per org per node | 🔴 Critical |
| Raft Quorum | ✅ 5 orderers | Maintain 5 for F=2 | ✅ Good |
| Separate TLS CA | ✅ Implemented | Already best practice | ✅ Good |
| CouchDB Per Peer | ✅ Implemented | Each peer has dedicated DB | ✅ Good |
| Private Data Collections | ⚠️ Unknown | Implement for sensitive data | 🟡 Medium |
| Chaincode Lifecycle | ✅ v2.0 | Using modern lifecycle | ✅ Good |

### 4.2 Kubernetes Best Practices

| Practice | Current Status | Target | Priority |
|----------|----------------|--------|----------|
| Pod Anti-Affinity | ❌ Not configured | Spread critical pods | 🔴 Critical |
| Resource Limits | ⚠️ Partial | Define for all pods | 🟡 Medium |
| PodDisruptionBudgets | ❌ Not configured | Ensure min availability | 🔴 Critical |
| Network Policies | ⚠️ Partial | Strict namespace isolation | 🟡 Medium |
| RBAC | ✅ K3s default | Review and harden | 🟡 Medium |
| Secrets Encryption | ⚠️ K8s Secrets | Consider Vault for prod | 🟢 Future |

### 4.3 Certificate Authority Best Practices

| Practice | Current Status | Target | Priority |
|----------|----------------|--------|----------|
| Root CA Offline | ❌ Running online | Move offline post-setup | 🟡 Medium |
| Intermediate CAs | ✅ Implemented | Per-org intermediate CAs | ✅ Good |
| Separate TLS PKI | ✅ Implemented | TLS CA separate | ✅ Good |
| Certificate Rotation | ⚠️ Manual | Automate with cert-manager | 🟡 Medium |
| Key Algorithm | ✅ ECDSA P-256 | Modern elliptic curve | ✅ Good |

---

## 5. Certificate Authority Architecture

### 5.1 Current CA Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CA HIERARCHY (fabric namespace)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          ┌──────────────┐                                    │
│                          │   ca-root    │ ← Root CA (Trust Anchor)          │
│                          │   Port 7054  │   Expires: Oct 2040               │
│                          └──────┬───────┘                                    │
│                                 │                                            │
│           ┌─────────────────────┼─────────────────────┐                      │
│           │                     │                     │                      │
│    ┌──────┴──────┐       ┌──────┴──────┐       ┌──────┴──────┐              │
│    │  ca-org1    │       │  ca-org2    │       │ ca-orderer  │              │
│    │  Port 9054  │       │  Port 10054 │       │  Port 8054  │              │
│    └─────────────┘       └─────────────┘       └─────────────┘              │
│    Issues: Org1 MSP      Issues: Org2 MSP      Issues: Orderer MSP          │
│                                                                              │
│                          ┌──────────────┐                                    │
│                          │   ca-tls     │ ← Dedicated TLS CA                │
│                          │  Port 11054  │   (Best Practice!)                │
│                          └──────────────┘                                    │
│                          Issues all TLS certificates                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Certificate Types

| Type | Issued By | Usage | Validity |
|------|-----------|-------|----------|
| Enrollment | Org CAs | Identity authentication | 1 year |
| TLS Server | TLS CA | gRPC/HTTP TLS | 1 year |
| TLS Client | TLS CA | Mutual TLS (mTLS) | 1 year |
| Admin | Org CAs | Channel/chaincode admin | 1 year |
| Orderer | Orderer CA | Ordering service | 1 year |

### 5.3 Certificate Rotation Script

```bash
#!/bin/bash
# /root/scripts/rotate-fabric-certs.sh

check_cert_expiry() {
  kubectl get secrets -n fabric -o json | \
    jq -r '.items[] | select(.data["tls-cert.pem"]) | .metadata.name' | \
    while read secret; do
      echo "Checking: $secret"
      kubectl get secret $secret -n fabric -o jsonpath='{.data.tls-cert\.pem}' | \
        base64 -d | openssl x509 -noout -enddate
    done
}

rotate_peer_cert() {
  PEER=$1
  ORG=$2

  # Enroll new certificate
  fabric-ca-client enroll \
    -u https://${PEER}-${ORG}:peerpw@ca-${ORG}:9054 \
    --tls.certfiles /etc/fabric/ca-cert.pem \
    -M /tmp/new-msp

  # Update Kubernetes secret
  kubectl create secret generic ${PEER}-${ORG}-crypto \
    --from-file=/tmp/new-msp \
    --dry-run=client -o yaml | \
    kubectl apply -f -

  # Rolling restart
  kubectl rollout restart statefulset ${PEER}-${ORG} -n fabric
}

# Run monthly
check_cert_expiry
```

---

## 6. Phase 0: Emergency Stabilization

**Duration:** Day 1-2
**Priority:** CRITICAL
**Prerequisite:** None

### 6.1 Clean VPS-1 Disk Space

**Risk Level:** Medium
**Estimated Time:** 1-2 hours

```bash
# On VPS-1 (72.60.210.201)

# 1. Document current state
docker ps -a > /root/docker-containers-before.txt
docker images > /root/docker-images-before.txt
df -h > /root/disk-before.txt

# 2. Prune Docker build cache (recovers ~70GB)
docker builder prune -a -f

# 3. Remove unused Docker images
docker image prune -a -f

# 4. Remove unused volumes (CAREFUL - verify first)
docker volume ls
docker volume prune -f

# 5. Verify space recovered
df -h /
# Expected: 79% → ~35%
```

### 6.2 Stop Duplicate Docker Compose Fabric

**Risk Level:** HIGH
**Estimated Time:** 2-4 hours

**CRITICAL DECISION REQUIRED:**
Before proceeding, determine which network is authoritative:
- Docker Compose network (17 containers)
- Kubernetes network (fabric namespace)

```bash
# On VPS-1 (72.60.210.201)

# 1. Find Docker Compose file location
find / -name "docker-compose*.yaml" -o -name "docker-compose*.yml" 2>/dev/null

# 2. Check Docker network ledger height
docker exec peer0.org1.prod.goodness.exchange peer channel getinfo -c gxchannel

# 3. Check K8s network ledger height
kubectl exec -n fabric peer0-org1-0 -c peer -- peer channel getinfo -c gxchannel

# 4. Compare block heights - higher = more recent

# 5. If K8s is authoritative, stop Docker Compose:
cd /path/to/docker-compose/directory
docker-compose stop  # Stop first, don't remove

# 6. Verify no port conflicts
netstat -tlnp | grep -E "7050|7051|5984"

# 7. Only after confirming K8s works:
docker-compose down  # Remove containers (keeps volumes)
```

### 6.3 Investigate Backend Service Health

**Risk Level:** Low
**Estimated Time:** 2-4 hours

```bash
# Check failing pods
kubectl get pods -n backend-mainnet | grep -v Running

# Check svc-tokenomics (0/3)
kubectl logs -n backend-mainnet -l app=svc-tokenomics --tail=100
kubectl describe pod -n backend-mainnet -l app=svc-tokenomics

# Check events for errors
kubectl get events -n backend-mainnet --sort-by='.lastTimestamp' | tail -30

# Check outbox-submitter connectivity to Fabric
kubectl logs -n backend-mainnet -l app=outbox-submitter --tail=200 | grep -i error

# Common fixes:
kubectl rollout restart deployment -n backend-mainnet svc-tokenomics
kubectl rollout restart deployment -n backend-mainnet svc-governance
kubectl rollout restart deployment -n backend-mainnet outbox-submitter

# Verify fix
kubectl get pods -n backend-mainnet -w
```

### 6.4 Phase 0 Success Criteria

- [ ] VPS-1 disk usage < 50%
- [ ] Single Fabric network running (K8s only)
- [ ] No port conflicts on VPS-1
- [ ] All backend services showing Ready status
- [ ] Outbox-submitter restart count stabilized

---

## 7. Phase 1: Pre-Migration Preparation

**Duration:** Day 2-3
**Priority:** HIGH

### 7.1 Install Docker on VPS-3

VPS-3 (72.61.81.3) currently has NO Docker installed.

```bash
# On VPS-3 (72.61.81.3)

# Install Docker CE
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Configure Docker daemon
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF

# Start Docker
systemctl enable --now docker

# Verify
docker --version
docker info
```

### 7.2 Create Full Pre-Migration Backup

```bash
#!/bin/bash
# /root/scripts/pre-migration-backup.sh

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/backups/pre-migration-$BACKUP_DATE"
mkdir -p $BACKUP_DIR

echo "=== Starting Pre-Migration Backup: $BACKUP_DATE ==="

# 1. Kubernetes resources
echo "Backing up Kubernetes resources..."
for ns in fabric fabric-testnet backend-mainnet backend-testnet monitoring; do
  kubectl get all -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-all.yaml
  kubectl get secrets -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-secrets.yaml
  kubectl get configmaps -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-configmaps.yaml
  kubectl get pvc -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-pvc.yaml
done

# 2. Fabric crypto materials
echo "Backing up Fabric crypto..."
kubectl get secrets -n fabric -o json | \
  jq -r '.items[] | select(.metadata.name | contains("crypto")) | @base64' \
  > $BACKUP_DIR/fabric-crypto-secrets.b64

# 3. PostgreSQL database
echo "Backing up PostgreSQL..."
kubectl exec -n backend-mainnet postgres-0 -- pg_dumpall -U postgres \
  > $BACKUP_DIR/postgres-full.sql

# 4. Redis data
echo "Backing up Redis..."
kubectl exec -n backend-mainnet redis-0 -- redis-cli BGSAVE
sleep 5
kubectl cp backend-mainnet/redis-0:/data/dump.rdb $BACKUP_DIR/redis-dump.rdb

# 5. Create archive
echo "Creating archive..."
tar -czvf /root/backups/gx-pre-migration-$BACKUP_DATE.tar.gz -C $BACKUP_DIR .

# 6. Upload to Google Drive (if rclone configured)
if command -v rclone &> /dev/null; then
  echo "Uploading to Google Drive..."
  rclone copy /root/backups/gx-pre-migration-$BACKUP_DATE.tar.gz \
    gdrive-backup:GX-Backups/pre-migration/
fi

echo "=== Pre-Migration Backup Complete ==="
```

### 7.3 Pre-Migration Checklist

```markdown
## Pre-Migration Checklist

### Infrastructure
- [ ] Docker installed on VPS-5 (72.61.81.3)
- [ ] All K3s nodes healthy (`kubectl get nodes`)
- [ ] All pods running (`kubectl get pods -A | grep -v Running`)
- [ ] Disk space > 50% free on all servers
- [ ] Memory usage < 80% on all servers

### Backups
- [ ] Full pre-migration backup completed
- [ ] PostgreSQL backup verified (can restore)
- [ ] Redis backup verified
- [ ] Fabric crypto materials backed up
- [ ] Kubernetes resources exported
- [ ] Backup uploaded to Google Drive

### Network
- [ ] Inter-server connectivity tested (ping, nc)
- [ ] Required ports open on firewall
- [ ] DNS records verified
- [ ] Cloudflare configuration documented

### Security
- [ ] SSL certificates valid (> 30 days)
- [ ] Kubernetes secrets accessible
- [ ] Access credentials documented (secure storage)

### Communication
- [ ] Stakeholders notified of maintenance window
- [ ] Rollback plan documented
- [ ] Support contacts available
```

---

## 8. Phase 2: Security Hardening

**Duration:** Day 3-5
**Priority:** HIGH

### 8.1 SSH Key Authentication

```bash
# On your LOCAL machine, generate SSH key
ssh-keygen -t ed25519 -C "gx-admin@gxcoin.money" -f ~/.ssh/gx-admin

# Copy public key to each server
for IP in 72.60.210.201 72.61.116.210 72.61.81.3 217.196.51.190 195.35.36.174; do
  ssh-copy-id -i ~/.ssh/gx-admin.pub root@$IP
done

# Test key-based login BEFORE disabling password auth
for IP in 72.60.210.201 72.61.116.210 72.61.81.3 217.196.51.190 195.35.36.174; do
  ssh -i ~/.ssh/gx-admin root@$IP "echo 'SSH key working on' \$(hostname)"
done

# On EACH server, harden SSH config
cat >> /etc/ssh/sshd_config << 'EOF'
# Security hardening
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
MaxAuthTries 3
LoginGraceTime 60
EOF

systemctl restart sshd
```

### 8.2 Disable Unnecessary Services

```bash
# On VPS-1, VPS-3, VPS-4 (NOT VPS-5 which needs Apache)
systemctl stop httpd
systemctl disable httpd

# On ALL servers - disable rpcbind if NFS not used
systemctl stop rpcbind
systemctl disable rpcbind

# Verify
systemctl list-units --type=service --state=running
```

### 8.3 Firewall Hardening

```bash
# On MainNet servers (VPS-1, VPS-2, VPS-3)

# Verify firewalld is active
systemctl enable --now firewalld

# Create zone for K3s cluster communication
firewall-cmd --permanent --new-zone=k3s-cluster 2>/dev/null || true
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.60.210.201
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.61.116.210
firewall-cmd --permanent --zone=k3s-cluster --add-source=72.61.81.3

# Allow K3s ports only from cluster members
firewall-cmd --permanent --zone=k3s-cluster --add-port=6443/tcp   # API Server
firewall-cmd --permanent --zone=k3s-cluster --add-port=2379-2380/tcp  # etcd
firewall-cmd --permanent --zone=k3s-cluster --add-port=10250/tcp  # Kubelet
firewall-cmd --permanent --zone=k3s-cluster --add-port=10251/tcp  # Scheduler
firewall-cmd --permanent --zone=k3s-cluster --add-port=10252/tcp  # Controller

# Allow public services
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh

# Reload
firewall-cmd --reload
firewall-cmd --list-all-zones
```

---

## 9. Phase 3: Infrastructure Setup

**Duration:** Day 5-8
**Priority:** HIGH

### 9.1 Apply PodDisruptionBudgets

```yaml
# /root/k8s/pdb-orderers.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orderer-pdb
  namespace: fabric
spec:
  minAvailable: 3  # Maintain Raft quorum (3 of 5)
  selector:
    matchLabels:
      app: orderer

---
# /root/k8s/pdb-peers-org1.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: peer-org1-pdb
  namespace: fabric
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: peer
      org: org1

---
# /root/k8s/pdb-peers-org2.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: peer-org2-pdb
  namespace: fabric
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: peer
      org: org2
```

```bash
kubectl apply -f /root/k8s/pdb-orderers.yaml
kubectl apply -f /root/k8s/pdb-peers-org1.yaml
kubectl apply -f /root/k8s/pdb-peers-org2.yaml
kubectl get pdb -n fabric
```

### 9.2 Apply Network Policies

```yaml
# /root/k8s/networkpolicy-fabric.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fabric-isolation
  namespace: fabric
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from same namespace
  - from:
    - namespaceSelector:
        matchLabels:
          name: fabric
  # Allow from backend-mainnet
  - from:
    - namespaceSelector:
        matchLabels:
          name: backend-mainnet
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  # Allow from partner (VPS-5)
  - from:
    - ipBlock:
        cidr: 195.35.36.174/32
    ports:
    - protocol: TCP
      port: 7050
    - protocol: TCP
      port: 7051
  egress:
  # Allow DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Allow same namespace
  - to:
    - namespaceSelector:
        matchLabels:
          name: fabric
  # Allow external communication
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 7050
    - protocol: TCP
      port: 7051
```

```bash
kubectl label namespace fabric name=fabric
kubectl label namespace backend-mainnet name=backend-mainnet
kubectl label namespace ingress-nginx name=ingress-nginx
kubectl apply -f /root/k8s/networkpolicy-fabric.yaml
kubectl get networkpolicy -n fabric
```

### 9.3 Apply Pod Anti-Affinity

```yaml
# Example for orderer StatefulSet patch
# /root/k8s/orderer-antiaffinity-patch.yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - orderer
            topologyKey: kubernetes.io/hostname
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.gx.io/role
                operator: In
                values:
                - mainnet-primary
                - mainnet-secondary
                - mainnet-tertiary
```

---

## 10. Phase 4: Architecture Restructuring

**Duration:** Day 8-14
**Priority:** HIGH
**Risk Level:** HIGH - Requires maintenance window

### 10.1 Migrate TestNet to VPS-4 (Standalone)

**Option A: Fresh Installation (Recommended)**

```bash
# On VPS-4 (217.196.51.190)

# 1. Drain and remove from cluster
kubectl drain srv1089624.hstgr.cloud --ignore-daemonsets --delete-emptydir-data --force

# From another control-plane node:
kubectl delete node srv1089624.hstgr.cloud

# 2. Uninstall K3s on VPS-4
/usr/local/bin/k3s-uninstall.sh

# 3. Clean up
rm -rf /etc/rancher /var/lib/rancher

# 4. Install fresh K3s standalone
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init=false \
  --disable traefik \
  --write-kubeconfig-mode 644

# 5. Wait for node ready
kubectl get nodes

# 6. Create namespaces
kubectl create namespace fabric-devnet
kubectl create namespace fabric-testnet
kubectl create namespace backend-devnet
kubectl create namespace backend-testnet

# 7. Deploy TestNet Fabric
# [Apply TestNet manifests from /root/k8s/testnet/]

# 8. Deploy TestNet Backend
# [Apply Backend manifests]
```

### 10.2 Remove TestNet from MainNet Cluster

```bash
# From MainNet cluster (VPS-3)

# 1. Delete TestNet namespaces
kubectl delete namespace fabric-testnet
kubectl delete namespace backend-testnet

# 2. Verify removal
kubectl get pods -A | grep testnet
```

### 10.3 Promote VPS-2 to Control-Plane

```bash
# On VPS-2 (72.61.116.210)

# 1. Stop K3s agent
systemctl stop k3s-agent

# 2. Uninstall agent
/usr/local/bin/k3s-agent-uninstall.sh

# 3. Get token from VPS-1
TOKEN=$(ssh root@72.60.210.201 "cat /var/lib/rancher/k3s/server/node-token")

# 4. Join as server (control-plane)
curl -sfL https://get.k3s.io | K3S_TOKEN=$TOKEN sh -s - server \
  --server https://72.60.210.201:6443

# 5. Verify
kubectl get nodes
# Should show: control-plane,etcd,master for VPS-2
```

### 10.4 Rebalance Fabric Components

```bash
# Apply node affinity to redistribute components
# This triggers rolling updates

# Example: Move orderer1 to VPS-2
kubectl patch statefulset orderer1 -n fabric --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [{
            "matchExpressions": [{
              "key": "kubernetes.io/hostname",
              "operator": "In",
              "values": ["srv1117946.hstgr.cloud"]
            }]
          }]
        }
      }
    }
  }
]'

# Force reschedule
kubectl rollout restart statefulset orderer1 -n fabric

# Verify new placement
kubectl get pods -n fabric -o wide | grep orderer
```

---

## 11. Phase 5: Backup Implementation

**Duration:** Day 7-10 (parallel with Phase 4)
**Priority:** HIGH

### 11.1 Install rclone on All Servers

```bash
# On ALL servers
curl https://rclone.org/install.sh | bash

# Configure Google Drive (interactive)
rclone config
# n) New remote
# name: gdrive-backup
# Storage: 17 (Google Drive)
# client_id: (leave blank)
# client_secret: (leave blank)
# scope: 1 (full access)
# root_folder_id: (leave blank)
# service_account_file: (leave blank)
# Edit advanced config: n
# Use auto config: y (follow browser auth)

# Verify
rclone lsd gdrive-backup:

# Create backup directories
rclone mkdir gdrive-backup:GX-Backups/vps1-website
rclone mkdir gdrive-backup:GX-Backups/vps2-devtest
rclone mkdir gdrive-backup:GX-Backups/mainnet/daily
rclone mkdir gdrive-backup:GX-Backups/mainnet/weekly
rclone mkdir gdrive-backup:GX-Backups/pre-migration
```

### 11.2 Backup Schedule

| Type | Frequency | Retention | Target |
|------|-----------|-----------|--------|
| PostgreSQL | Every 6 hours | 7 days | Local + GDrive |
| Redis | Every 6 hours | 7 days | Local + GDrive |
| Fabric Crypto | Daily | 90 days | GDrive |
| K8s Resources | Daily | 30 days | GDrive |
| Full System | Weekly | 12 weeks | GDrive |
| Pre-Migration | Before changes | Permanent | GDrive |

### 11.3 Cron Schedule

```bash
# VPS-1 (MainNet Primary)
0 4 * * * /root/scripts/backup-mainnet.sh >> /var/log/backup.log 2>&1
0 */6 * * * /root/scripts/backup-mainnet-incremental.sh >> /var/log/backup-incr.log 2>&1

# VPS-4 (DevNet/TestNet)
0 3 * * * /root/scripts/backup-vps4.sh >> /var/log/backup.log 2>&1

# VPS-5 (Website)
0 2 * * * /root/scripts/backup-vps5.sh >> /var/log/backup.log 2>&1
```

---

## 12. Phase 6: Testing & Validation

**Duration:** Day 14-16
**Priority:** HIGH

### 12.1 Network Connectivity Tests

```bash
#!/bin/bash
# /root/test-scripts/test-network-connectivity.sh

echo "=========================================="
echo "NETWORK CONNECTIVITY TEST SUITE"
echo "=========================================="

SERVERS=(
  "72.60.210.201:VPS-1"
  "72.61.116.210:VPS-2"
  "72.61.81.3:VPS-3"
  "217.196.51.190:VPS-4"
  "195.35.36.174:VPS-5"
)

# Test 1: ICMP Ping
echo "=== TEST 1: ICMP Ping ==="
for server in "${SERVERS[@]}"; do
  IP=$(echo $server | cut -d: -f1)
  NAME=$(echo $server | cut -d: -f2)
  if ping -c 3 -W 2 $IP > /dev/null 2>&1; then
    echo "✅ $NAME ($IP): Reachable"
  else
    echo "❌ $NAME ($IP): Unreachable"
  fi
done

# Test 2: SSH
echo ""
echo "=== TEST 2: SSH (Port 22) ==="
for server in "${SERVERS[@]}"; do
  IP=$(echo $server | cut -d: -f1)
  NAME=$(echo $server | cut -d: -f2)
  if nc -zv -w 3 $IP 22 2>&1 | grep -q succeeded; then
    echo "✅ $NAME: SSH accessible"
  else
    echo "❌ $NAME: SSH not accessible"
  fi
done

# Test 3: Kubernetes API
echo ""
echo "=== TEST 3: K8s API (Port 6443) ==="
for IP in 72.60.210.201 72.61.116.210 72.61.81.3; do
  if nc -zv -w 3 $IP 6443 2>&1 | grep -q succeeded; then
    echo "✅ $IP: K8s API accessible"
  else
    echo "⚠️ $IP: K8s API not accessible"
  fi
done

# Test 4: DNS Resolution
echo ""
echo "=== TEST 4: DNS Resolution ==="
for domain in api.gxcoin.money gxcoin.money wallet.gxcoin.money goodness.exchange; do
  IP=$(dig +short $domain | head -1)
  if [ -n "$IP" ]; then
    echo "✅ $domain → $IP"
  else
    echo "❌ $domain: DNS resolution failed"
  fi
done

echo ""
echo "=========================================="
echo "CONNECTIVITY TEST COMPLETE"
echo "=========================================="
```

### 12.2 Fabric Network Tests

```bash
#!/bin/bash
# /root/test-scripts/test-fabric-network.sh

echo "=========================================="
echo "HYPERLEDGER FABRIC NETWORK TEST SUITE"
echo "=========================================="

# Test 1: Orderer health
echo "=== TEST 1: Orderer Health ==="
for i in 0 1 2 3 4; do
  POD=$(kubectl get pods -n fabric -l orderer=orderer$i -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if kubectl exec -n fabric $POD -- curl -s http://localhost:8443/healthz 2>/dev/null | grep -q OK; then
    echo "✅ Orderer $i: Healthy"
  else
    echo "❌ Orderer $i: Not healthy"
  fi
done

# Test 2: Peer health
echo ""
echo "=== TEST 2: Peer Health ==="
PEER_PODS=$(kubectl get pods -n fabric -l app=peer -o jsonpath='{.items[*].metadata.name}')
for pod in $PEER_PODS; do
  STATUS=$(kubectl exec -n fabric $pod -c peer -- peer node status 2>/dev/null | grep -c STARTED)
  if [ "$STATUS" -gt 0 ]; then
    echo "✅ $pod: Running"
  else
    echo "❌ $pod: Not running"
  fi
done

# Test 3: Ledger height consistency
echo ""
echo "=== TEST 3: Ledger Height ==="
declare -A HEIGHTS
for pod in $PEER_PODS; do
  HEIGHT=$(kubectl exec -n fabric $pod -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
  HEIGHTS[$pod]=$HEIGHT
  echo "$pod: Block height = $HEIGHT"
done

UNIQUE=$(echo "${HEIGHTS[@]}" | tr ' ' '\n' | sort -u | wc -l)
if [ "$UNIQUE" -eq 1 ]; then
  echo "✅ All peers have consistent ledger height"
else
  echo "⚠️ Ledger heights differ"
fi

# Test 4: Chaincode query
echo ""
echo "=== TEST 4: Chaincode Query ==="
PEER0=$(kubectl get pods -n fabric -l peer=peer0-org1 -o jsonpath='{.items[0].metadata.name}')
RESULT=$(kubectl exec -n fabric $PEER0 -c peer -- peer chaincode query -C gxchannel -n gxtv3 -c '{"function":"GetMetadata","Args":[]}' 2>/dev/null)
if [ -n "$RESULT" ]; then
  echo "✅ Chaincode query successful"
else
  echo "❌ Chaincode query failed"
fi

echo ""
echo "=========================================="
echo "FABRIC TEST COMPLETE"
echo "=========================================="
```

### 12.3 End-to-End Transaction Test

```bash
#!/bin/bash
# /root/test-scripts/test-e2e-transaction.sh

echo "=========================================="
echo "END-TO-END TRANSACTION TEST"
echo "=========================================="

# Step 1: API Health
echo "=== Step 1: Check API Health ==="
HEALTH=$(curl -s https://api.gxcoin.money/health 2>/dev/null)
if [ -n "$HEALTH" ]; then
  echo "✅ API is healthy"
else
  echo "❌ API not responding"
  exit 1
fi

# Step 2: Block Production
echo ""
echo "=== Step 2: Check Block Production ==="
PEER_POD=$(kubectl get pods -n fabric -l peer=peer0-org1 -o jsonpath='{.items[0].metadata.name}')
HEIGHT_BEFORE=$(kubectl exec -n fabric $PEER_POD -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
echo "Current block height: $HEIGHT_BEFORE"

sleep 10

HEIGHT_AFTER=$(kubectl exec -n fabric $PEER_POD -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
echo "Block height after 10s: $HEIGHT_AFTER"

if [ "$HEIGHT_AFTER" -ge "$HEIGHT_BEFORE" ]; then
  echo "✅ Blockchain operational"
else
  echo "⚠️ No new blocks (may be normal)"
fi

# Step 3: Projector Health
echo ""
echo "=== Step 3: Check Projector ==="
PROJECTOR_POD=$(kubectl get pods -n backend-mainnet -l app=projector -o jsonpath='{.items[0].metadata.name}')
ERRORS=$(kubectl logs -n backend-mainnet $PROJECTOR_POD --tail=50 2>/dev/null | grep -ci error)
if [ "$ERRORS" -lt 5 ]; then
  echo "✅ Projector healthy (errors: $ERRORS)"
else
  echo "⚠️ Projector has errors: $ERRORS"
fi

# Step 4: Outbox Health
echo ""
echo "=== Step 4: Check Outbox-submitter ==="
OUTBOX_POD=$(kubectl get pods -n backend-mainnet -l app=outbox-submitter -o jsonpath='{.items[0].metadata.name}')
RESTARTS=$(kubectl get pod $OUTBOX_POD -n backend-mainnet -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo "Restart count: $RESTARTS"
if [ "$RESTARTS" -lt 50 ]; then
  echo "✅ Outbox-submitter stable"
else
  echo "⚠️ High restart count"
fi

echo ""
echo "=========================================="
echo "E2E TEST COMPLETE"
echo "=========================================="
```

### 12.4 Post-Migration Validation Checklist

```markdown
## Post-Migration Validation Checklist

### Infrastructure
- [ ] All K8s nodes in Ready state
- [ ] All pods Running (no CrashLoopBackOff)
- [ ] PVCs bound and accessible
- [ ] Resource usage within limits
- [ ] VPS-4 running standalone DevNet/TestNet
- [ ] VPS-1, 2, 3 as 3-node MainNet cluster

### Fabric Network
- [ ] All 5 orderers healthy and in Raft consensus
- [ ] All 4 peers synced (same block height)
- [ ] Chaincode responding to queries
- [ ] Channel configuration intact
- [ ] Anchor peers correctly configured

### Databases
- [ ] PostgreSQL primary accessible
- [ ] PostgreSQL replication working
- [ ] Redis master accessible
- [ ] Redis replication working
- [ ] CouchDB instances responding

### Applications
- [ ] Frontend loading correctly
- [ ] API endpoints responding
- [ ] Authentication working
- [ ] All backend services healthy (3/3)
- [ ] Projector processing events
- [ ] Outbox-submitter stable (<10 restarts/day)

### Network
- [ ] DNS resolving correctly
- [ ] SSL certificates valid
- [ ] Cloudflare proxy active
- [ ] Inter-server connectivity working
- [ ] Partner peer connected (VPS-5)

### Backup
- [ ] rclone configured on all 5 servers
- [ ] Backup to Google Drive working
- [ ] Test restore completed successfully
- [ ] Backup schedule active
```

---

## 13. Phase 7: Monitoring & Operations

**Duration:** Day 16-18
**Priority:** MEDIUM

### 13.1 Add Fabric Metrics Exporter

```yaml
# /root/k8s/servicemonitor-fabric.yaml
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
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fabric-orderers
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: orderer
  namespaceSelector:
    matchNames:
    - fabric
  endpoints:
  - port: operations
    path: /metrics
    interval: 30s
```

### 13.2 Configure Critical Alerts

```yaml
# /root/k8s/prometheus-rules-fabric.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: fabric-alerts
  namespace: monitoring
spec:
  groups:
  - name: fabric
    rules:
    - alert: FabricOrdererDown
      expr: up{job="fabric-orderers"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Fabric Orderer is down"

    - alert: FabricPeerDown
      expr: up{job="fabric-peers"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Fabric Peer is down"

    - alert: DiskSpaceCritical
      expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Disk space below 20%"

    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Pod is crash looping"

    - alert: BackupJobFailed
      expr: time() - backup_last_success_timestamp > 86400
      for: 1h
      labels:
        severity: critical
      annotations:
        summary: "Backup has not succeeded in 24 hours"
```

### 13.3 Grafana Dashboards

Create dashboards for:
1. **Fabric Network Overview** - Orderers, Peers, Block height
2. **Peer Performance** - Endorsements, Gossip
3. **Orderer Metrics** - Raft consensus, Block creation
4. **Backend Services** - Request rates, Latency
5. **Database Metrics** - PostgreSQL, Redis, CouchDB
6. **Node Resources** - CPU, Memory, Disk per VPS

---

## 14. Cloudflare Integration

### 14.1 DNS Configuration

| Record | Type | Value | Proxy |
|--------|------|-------|-------|
| gxcoin.money | A | 195.35.36.174 | Yes |
| www.gxcoin.money | CNAME | gxcoin.money | Yes |
| api.gxcoin.money | A | 72.60.210.201 | Yes |
| wallet.gxcoin.money | A | 72.60.210.201 | Yes |
| goodness.exchange | A | 72.60.210.201 | Yes |

### 14.2 Recommended Settings

```
SSL/TLS:
├── Encryption Mode: Full (Strict)
├── Always Use HTTPS: ON
├── Minimum TLS Version: 1.2
└── Opportunistic Encryption: ON

Security:
├── Security Level: Medium
├── Bot Fight Mode: ON
├── Browser Integrity Check: ON
└── Rate Limiting: 100 req/min per IP

Caching:
├── api.gxcoin.money/*: Bypass Cache
├── wallet.gxcoin.money/*: Security Level High
└── gxcoin.money/static/*: Cache 1 month
```

---

## 15. Operational Runbooks

### 15.1 Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Infrastructure | [Name] | 24/7 |
| Blockchain | [Name] | Business hours |
| Database | [Name] | On-call |

### 15.2 Quick Reference Commands

```bash
# Cluster health
kubectl get nodes && kubectl get pods -A | grep -v Running

# Fabric network
kubectl get pods -n fabric -l app=orderer
kubectl get pods -n fabric -l app=peer

# Backend services
kubectl get pods -n backend-mainnet

# View logs
kubectl logs -f deployment/svc-identity -n backend-mainnet
kubectl logs -f statefulset/orderer0 -n fabric -c orderer

# Restart deployment
kubectl rollout restart deployment/svc-identity -n backend-mainnet

# Check resource usage
kubectl top nodes && kubectl top pods -n fabric
```

### 15.3 Incident Response

```
1. DETECT → Alert / User report / Monitoring
2. ASSESS → Priority 1 (Production/Data at risk) or Priority 2 (Performance)
3. COMMUNICATE → Notify stakeholders, Update status
4. MITIGATE → Restart/Scale or Check consensus or Restore backup
5. RESOLVE → Apply fix, Verify services
6. REVIEW → Document root cause, Update runbooks
```

---

## 16. Appendices

### Appendix A: Implementation Schedule

| Phase | Duration | Start | Dependencies |
|-------|----------|-------|--------------|
| Phase 0: Emergency | Day 1-2 | Immediate | None |
| Phase 1: Preparation | Day 2-3 | After Phase 0 | Phase 0 |
| Phase 2: Security | Day 3-5 | Parallel | None |
| Phase 3: Infrastructure | Day 5-8 | After Phase 1 | Phase 1 |
| Phase 4: Restructuring | Day 8-14 | After Phase 3 | Phase 3 |
| Phase 5: Backup | Day 7-10 | Parallel | Phase 2 |
| Phase 6: Testing | Day 14-16 | After Phase 4 | Phase 4 |
| Phase 7: Monitoring | Day 16-18 | After Phase 6 | Phase 6 |

**Total Duration: ~18 working days**

### Appendix B: Rollback Procedures

**Phase 0 Rollback:**
```bash
# Restart Docker Compose if needed
cd /path/to/compose
docker-compose up -d
```

**Phase 4 Rollback:**
```bash
# Restore etcd from snapshot
k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot
```

### Appendix C: File Locations

| Item | Location |
|------|----------|
| Fabric crypto | /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/organizations |
| Backend code | /home/sugxcoin/prod-blockchain/gx-protocol-backend |
| K8s manifests | /root/k8s/ |
| Test scripts | /root/test-scripts/ |
| Backup scripts | /root/scripts/ |
| Audit docs | /home/sugxcoin/prod-blockchain/gx-infra-arch/ |

---

## Document Approval

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Dec 11, 2025 | Previous Audit | Initial plan |
| 2.0 | Dec 11, 2025 | Previous Audit | Added testing, Cloudflare |
| 3.0 | Dec 13, 2025 | Current Audit | Unified plan, Phase 0, correct IPs |

**Approval Required:**
- [ ] Technical Lead
- [ ] Operations Team
- [ ] Stakeholder Acknowledgment

---

**END OF DOCUMENT**
