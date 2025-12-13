# GX Coin Protocol Infrastructure Audit Report

**Audit Date:** December 13, 2025
**Auditor:** Infrastructure Assessment Team
**Report Version:** 1.0

---

## Executive Summary

This audit reveals **significant architectural misalignment** between the intended infrastructure design and the current deployment state. The primary issues are:

1. **Duplicate Fabric Deployments** - VPS-3 runs BOTH Docker Compose and Kubernetes Fabric networks simultaneously
2. **Architectural Mismatch** - All 4 high-spec servers are in a single K3s cluster instead of separated environments
3. **Missing Backup Coverage** - Only PostgreSQL/Redis have backups; no server-level or blockchain backups
4. **Disk Space Critical** - VPS-3 at 79% with 70GB reclaimable Docker build cache
5. **Service Health Issues** - Multiple backend pods in unhealthy states; outbox-submitter with excessive restarts

---

## Inventory Summary

### Server Overview

| VPS | IP Address | Hostname | Role | Specs | Disk Used | RAM Used |
|-----|------------|----------|------|-------|-----------|----------|
| VPS-1 | 195.35.36.174 | srv711725.hstgr.cloud | Low-Spec | 2 vCPU / 8GB / 100GB | 14% | 27% |
| VPS-2 | 217.196.51.190 | srv1089624.hstgr.cloud | High-Spec | 8 vCPU / 32GB / 400GB | 59% | 23% |
| VPS-3 | 72.60.210.201 | srv1089618.hstgr.cloud | High-Spec | 8 vCPU / 32GB / 400GB | **79%** | **67%** |
| VPS-4 | 72.61.116.210 | srv1117946.hstgr.cloud | High-Spec | 8 vCPU / 32GB / 400GB | 19% | 17% |
| VPS-5 | 72.61.81.3 | srv1092158.hstgr.cloud | High-Spec | 8 vCPU / 32GB / 400GB | 52% | 22% |

### Operating System
All servers: **AlmaLinux 10.0/10.1 (Purple Lion/Heliotrope Lion)**
Kernel: 6.12.0-55.40.1.el10_0.x86_64

---

## Current Architecture vs Intended Architecture

### Intended Design

```
VPS-1 (Low-Spec)     → Website + Partner Simulator (standalone)
VPS-2 (High-Spec)    → DevNet + TestNet (development environment)
VPS-3 (High-Spec)    → MainNet Node 1 (Primary)
VPS-4 (High-Spec)    → MainNet Node 2
VPS-5 (High-Spec)    → MainNet Node 3
```

### Actual Deployment

```
VPS-1 (STANDALONE)
├── K3s single-node cluster
├── Website (Docker: gx-marketing-site)
├── Apache HTTPD (reverse proxy)
└── Partner Simulator (K8s: gx-partnerorg1 namespace)
    ├── partnerorg1-peer-0
    └── partnerorg1-cli

VPS-2, VPS-3, VPS-4, VPS-5 (SINGLE 4-NODE K3S CLUSTER)
├── VPS-2: Control-plane + etcd
├── VPS-3: Control-plane + etcd (PRIMARY)
├── VPS-4: Worker node
└── VPS-5: Control-plane + etcd

NAMESPACES IN SHARED CLUSTER:
├── fabric (MainNet Blockchain)
├── fabric-testnet (TestNet Blockchain)
├── backend-mainnet (Backend Services)
├── backend-testnet (Backend Services)
├── monitoring (Grafana, Prometheus, Loki)
├── cert-manager (TLS Certificates)
├── ingress-nginx (Ingress Controller)
├── metallb-system (Load Balancer)
└── registry (Docker Registry)
```

### CRITICAL: VPS-3 Duplicate Deployments

VPS-3 is running TWO separate Fabric networks:

**Docker Compose Network (17 containers):**
- 5 Orderers (orderer0-4.ordererorg.prod.goodness.exchange)
- 4 Peers (peer0/1.org1/org2.prod.goodness.exchange)
- 4 CouchDB instances (couchdb0-3)
- 3 Chaincode containers
- 1 CA PostgreSQL (postgres.ca)

**Kubernetes Network (fabric namespace):**
- 5 Orderers (orderer0-4)
- 4 Peers (peer0/1-org1/org2)
- 4 CouchDB instances
- 5 Certificate Authorities
- 1 Chaincode

This creates **resource conflict, port conflicts, and potential data inconsistency**.

---

## Detailed Findings by Server

### VPS-1 (195.35.36.174) - Website Server

**Status:** Partially Compliant

**Running Services:**
- K3s (standalone cluster)
- Docker (gx-marketing-site:green on port 3003)
- Apache HTTPD (ports 80, 443) - reverse proxy to Docker app
- Partner Simulator (K8s gx-partnerorg1 namespace)

**Issues Found:**
| ID | Severity | Issue | Impact |
|----|----------|-------|--------|
| V1-01 | Medium | Docker build cache: 4.6GB reclaimable | Wasted disk space |
| V1-02 | Medium | Unused Fabric images (736MB reclaimable) | Wasted disk space |
| V1-03 | High | No backup configuration | Data loss risk |
| V1-04 | Low | Socat forwarding port 7050 | Potential security risk |

**Positive Findings:**
- Low resource utilization (14% disk, 27% RAM)
- Clean container setup
- Partner simulator correctly isolated

---

### VPS-2 (217.196.51.190) - Cluster Control-Plane

**Status:** Major Issues

**Role:** K3s control-plane node in 4-node cluster

**Running Services:**
- K3s control-plane (etcd member)
- Docker (not in use for containers)
- Apache HTTPD (unnecessary)

**Fabric MainNet Components on this node:**
- ca-orderer-0, ca-org1-0, ca-tls-0 (Certificate Authorities)
- orderer2-0
- peer0-org2-0
- couchdb-peer0-org1-0, couchdb-peer1-org2-0

**Backend Components:**
- postgres-2 (PostgreSQL HA replica)

**Issues Found:**
| ID | Severity | Issue | Impact |
|----|----------|-------|--------|
| V2-01 | Critical | MainNet and TestNet in same cluster | No isolation |
| V2-02 | High | Apache HTTPD running without purpose | Security risk |
| V2-03 | High | Unused Docker image (1.1GB reclaimable) | Wasted space |
| V2-04 | High | No dedicated backup configuration | Data loss risk |
| V2-05 | Medium | 59% disk usage trending high | Capacity planning needed |

---

### VPS-3 (72.60.210.201) - Intended MainNet Primary

**Status:** CRITICAL ISSUES

**Role:** K3s control-plane (appears to be primary based on activity)

**CRITICAL: Duplicate Fabric Networks**

This server runs BOTH:
1. **Docker Compose Fabric** (17 containers actively running)
2. **Kubernetes Fabric** (pods in fabric namespace)

**Docker Compose Network:**
```
Orderers: orderer0-4.ordererorg.prod.goodness.exchange (ports 27050-31050)
Peers: peer0/1.org1/org2.prod.goodness.exchange (ports 7051, 8051, 9051, 10051)
CouchDB: couchdb0-3 (ports 5984, 6984, 7984, 8984)
Chaincode: 3 dev-peer containers
CA DB: postgres.ca (port 5433)
```

**Kubernetes Fabric:**
```
orderer0-0, orderer3-0
peer0-org1-0
couchdb-peer1-org1-0
gxtv3-chaincode-0
```

**Issues Found:**
| ID | Severity | Issue | Impact |
|----|----------|-------|--------|
| V3-01 | **CRITICAL** | Duplicate Fabric deployments | Data inconsistency, conflicts |
| V3-02 | **CRITICAL** | 79% disk usage | Imminent capacity crisis |
| V3-03 | **CRITICAL** | 70GB Docker build cache | Major space waste |
| V3-04 | High | 67% RAM usage | Performance risk |
| V3-05 | High | Port conflicts between Docker/K8s | Service instability |
| V3-06 | High | No backup configuration | Data loss risk |
| V3-07 | Medium | Multiple old Docker images | Space waste |
| V3-08 | Medium | Apache HTTPD running | Unnecessary service |

**Docker Disk Usage Breakdown:**
```
Images:      6.6GB  (14% reclaimable)
Containers:  9.5KB
Volumes:     754MB
Build Cache: 76.2GB (70.5GB reclaimable - 92%)
```

---

### VPS-4 (72.61.116.210) - Intended MainNet Node 2

**Status:** Architectural Mismatch

**Role:** K3s WORKER node (not control-plane as expected for HA)

**Actual Workload:**
- **TestNet** (fabric-testnet namespace) - ENTIRE testnet runs here
- **Backend TestNet** (backend-testnet namespace)
- **Backend MainNet** database replicas (postgres-0, postgres-1, redis-0, redis-1)
- cert-manager

**Issues Found:**
| ID | Severity | Issue | Impact |
|----|----------|-------|--------|
| V4-01 | **CRITICAL** | Running TestNet instead of MainNet | Wrong environment |
| V4-02 | High | Worker node, not control-plane | Reduces HA capability |
| V4-03 | High | outbox-submitter 1353 restarts | Service failure |
| V4-04 | High | No backup configuration | Data loss risk |

**Positive Findings:**
- Low resource utilization (19% disk, 17% RAM)
- Clean Docker environment (no unused images)

---

### VPS-5 (72.61.81.3) - Intended MainNet Node 3

**Status:** Mostly Compliant (for current architecture)

**Role:** K3s control-plane

**Running MainNet Components:**
- ca-org2-0, ca-root-0 (Certificate Authorities)
- orderer1-0, orderer4-0
- peer1-org1-0, peer1-org2-0
- couchdb-peer0-org2-0
- postgres-0 (CA database)

**Backend Services:**
- Multiple svc-* pods (some unhealthy)

**Issues Found:**
| ID | Severity | Issue | Impact |
|----|----------|-------|--------|
| V5-01 | Medium | Apache HTTPD running (empty) | Unnecessary service |
| V5-02 | High | No backup configuration | Data loss risk |
| V5-03 | Medium | Some backend pods 0/1 Ready | Service degradation |
| V5-04 | Low | 52% disk usage | Monitor trending |

**Positive Findings:**
- Docker not installed (clean containerd-only setup)
- Correct MainNet components running

---

## Service Health Assessment

### Backend Services Status

| Service | Desired | Ready | Status |
|---------|---------|-------|--------|
| svc-admin | 3 | 3 | Healthy |
| svc-identity | 3 | 3 | Healthy |
| svc-governance | 3 | 1 | **Degraded** |
| svc-loanpool | 3 | 1 | **Degraded** |
| svc-organization | 3 | 1 | **Degraded** |
| svc-tax | 3 | 1 | **Degraded** |
| svc-tokenomics | 3 | 0 | **Failed** |
| outbox-submitter (mainnet) | 1 | 1 | Warning (140 restarts) |
| outbox-submitter (testnet) | 1 | 1 | **Critical (1353 restarts)** |
| projector (mainnet) | 1 | 1 | Healthy |
| projector (testnet) | 1 | 1 | Healthy |

### Database Services Status

| Service | Replicas | Status |
|---------|----------|--------|
| PostgreSQL (mainnet) | 3/3 | Healthy |
| Redis (mainnet) | 3/3 | Healthy |
| PostgreSQL (testnet) | 1/1 | Healthy |
| Redis (testnet) | 1/1 | Healthy |

### Fabric Network Status

**MainNet (fabric namespace):**
- 5/5 Orderers: Healthy
- 4/4 Peers: Healthy
- 4/4 CouchDB: Healthy
- 5/5 CAs: Healthy
- 1/1 Chaincode: Healthy

**TestNet (fabric-testnet namespace):**
- 3/3 Orderers: Healthy
- 2/2 Peers: Healthy
- 2/2 CouchDB: Healthy
- 1/1 Chaincode: Healthy

---

## Backup Assessment

### Current State

| Server | rclone | Scripts | K8s CronJob | Coverage |
|--------|--------|---------|-------------|----------|
| VPS-1 | No | No | No | **None** |
| VPS-2 | No | No | Yes (postgres, redis) | Partial |
| VPS-3 | No | No | Yes (via cluster) | Partial |
| VPS-4 | No | No | Yes (via cluster) | Partial |
| VPS-5 | No | No | Yes (via cluster) | Partial |

**What IS backed up:**
- PostgreSQL (mainnet): Every 6 hours via K8s CronJob
- Redis (mainnet): Every 6 hours via K8s CronJob

**What is NOT backed up:**
- VPS-1 (website, partner simulator, configs)
- Fabric crypto materials
- Fabric ledger data
- Certificate Authority databases
- System configurations
- Application code and configs

---

## Monitoring Assessment

### Current Stack (monitoring namespace)

| Component | Status | Purpose |
|-----------|--------|---------|
| Prometheus | Running | Metrics collection |
| Grafana | Running | Dashboards |
| Loki | Running | Log aggregation |
| Alertmanager | Running | Alert routing |
| Node Exporter | Running (all nodes) | System metrics |
| Promtail | Running (all nodes) | Log shipping |
| Kube-state-metrics | Running | K8s metrics |
| Postgres Exporter | Running | DB metrics |

**Gaps:**
- No Fabric-specific metrics exporters
- No dedicated CouchDB monitoring
- No external uptime monitoring

---

## Security Assessment

### Positive Findings

1. **Monarx Agent** - Security scanner running on all servers
2. **TLS Certificates** - cert-manager handling SSL/TLS
3. **Firewall** - Basic firewall rules in place
4. **SSH** - SSH running on standard port 22

### Security Concerns

| ID | Severity | Issue | Recommendation |
|----|----------|-------|----------------|
| SEC-01 | Critical | Same root password on all servers | Implement SSH keys, disable password auth |
| SEC-02 | High | Apache HTTPD running unnecessarily on VPS-2, VPS-3, VPS-5 | Disable or remove |
| SEC-03 | Medium | RPC Bind (port 111) open on all servers | Disable if not needed |
| SEC-04 | Medium | No network segmentation between environments | Implement network policies |
| SEC-05 | Low | VS Code server running on VPS-3 | Review remote access policies |

---

## Disk Space Analysis

### Current Usage

| Server | Total | Used | Available | % Used | Status |
|--------|-------|------|-----------|--------|--------|
| VPS-1 | 100GB | 14GB | 86GB | 14% | Healthy |
| VPS-2 | 400GB | 234GB | 166GB | 59% | Warning |
| VPS-3 | 400GB | 312GB | 88GB | **79%** | **Critical** |
| VPS-4 | 400GB | 75GB | 325GB | 19% | Healthy |
| VPS-5 | 400GB | 205GB | 195GB | 52% | Healthy |

### Reclaimable Space

| Server | Docker Build Cache | Docker Images | Total Reclaimable |
|--------|-------------------|---------------|-------------------|
| VPS-1 | 4.6GB | 736MB | ~5.3GB |
| VPS-2 | 0 | 1.1GB | ~1.1GB |
| VPS-3 | **70.5GB** | 952MB | **~71.5GB** |
| VPS-4 | 0 | 0 | 0 |
| VPS-5 | 0 | 0 | 0 |

---

## Issue Priority Matrix

### Critical (Immediate Action Required)

1. **VPS-3 Duplicate Fabric Networks** - Risk of data inconsistency and conflicts
2. **VPS-3 Disk Space (79%)** - Risk of service failure
3. **TestNet on VPS-4** - Architectural mismatch; should be on VPS-2
4. **Missing Backups** - No recovery capability for most data

### High Priority

5. **Backend Service Health** - 5 of 7 services degraded or failed
6. **Outbox-submitter Restarts** - Indicates connectivity or configuration issues
7. **VPS-4 as Worker Node** - Reduces MainNet HA capability
8. **Security: Shared Root Password** - Single point of compromise

### Medium Priority

9. **Unnecessary Apache HTTPD** - On VPS-2, VPS-3, VPS-5
10. **Unused Docker Images** - Wasting space across servers
11. **Network Isolation** - MainNet/TestNet share cluster
12. **Monitoring Gaps** - No Fabric-specific monitoring

### Low Priority

13. **Documentation** - Current state not documented
14. **RPC Bind Service** - Potentially unnecessary
15. **Disk Usage Trending** - VPS-2 and VPS-5 need monitoring

---

## Recommendations Summary

### Immediate Actions (24-48 hours)

1. **Clean VPS-3 disk space** - Run `docker system prune -a` and `docker builder prune`
2. **Stop Docker Compose Fabric on VPS-3** - Keep only Kubernetes deployment
3. **Investigate outbox-submitter crashes** - Check logs and Fabric connectivity
4. **Rotate root passwords** - Implement unique passwords or SSH keys

### Short-term Actions (1-2 weeks)

5. **Migrate TestNet to VPS-2** - Create dedicated testnet environment
6. **Promote VPS-4 to control-plane** - For MainNet HA
7. **Implement backup strategy** - Google Drive via rclone for all servers
8. **Disable unnecessary services** - Apache HTTPD on blockchain nodes
9. **Fix degraded backend services** - Investigate and resolve pod issues

### Medium-term Actions (1 month)

10. **Restructure architecture** - Separate DevNet/TestNet from MainNet
11. **Implement network policies** - Isolate environments within cluster
12. **Add Fabric monitoring** - Custom metrics for blockchain health
13. **Document architecture** - Maintain accurate infrastructure docs

---

## Appendix A: Server Access Details

| VPS | IP Address | SSH | Hostname |
|-----|------------|-----|----------|
| VPS-1 | 195.35.36.174 | Port 22 | srv711725.hstgr.cloud |
| VPS-2 | 217.196.51.190 | Port 22 | srv1089624.hstgr.cloud |
| VPS-3 | 72.60.210.201 | Port 22 | srv1089618.hstgr.cloud |
| VPS-4 | 72.61.116.210 | Port 22 | srv1117946.hstgr.cloud |
| VPS-5 | 72.61.81.3 | Port 22 | srv1092158.hstgr.cloud |

---

## Appendix B: Kubernetes Cluster Details

**Cluster Type:** K3s v1.33.5
**Container Runtime:** containerd 2.1.4-k3s1
**CNI:** Flannel (default K3s)
**Load Balancer:** MetalLB
**Ingress:** NGINX Ingress Controller
**Certificate Management:** cert-manager

**Etcd Members:**
- srv1089618.hstgr.cloud (VPS-3)
- srv1089624.hstgr.cloud (VPS-2)
- srv1092158.hstgr.cloud (VPS-5)

---

*End of Audit Report*
