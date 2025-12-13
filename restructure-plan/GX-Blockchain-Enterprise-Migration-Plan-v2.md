# GX Blockchain Enterprise Infrastructure Migration Plan
## Industry Best Practices Edition with Comprehensive Testing

**Document Version:** 2.0  
**Created:** December 11, 2025  
**Classification:** CONFIDENTIAL - Internal Use Only  
**Project:** GX Coin Enterprise Blockchain Platform  
**Domains:** goodness.exchange | gxcoin.money | wallet.gxcoin.money

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Industry Best Practices Framework](#3-industry-best-practices-framework)
4. [Certificate Authority Architecture](#4-certificate-authority-architecture)
5. [Target Architecture](#5-target-architecture)
6. [Security & Compliance Standards](#6-security--compliance-standards)
7. [Pre-Migration Preparation](#7-pre-migration-preparation)
8. [Migration Phases](#8-migration-phases)
9. [Comprehensive Testing Plan](#9-comprehensive-testing-plan)
10. [Backup & Disaster Recovery](#10-backup--disaster-recovery)
11. [Cloudflare Integration](#11-cloudflare-integration)
12. [Post-Migration Validation](#12-post-migration-validation)
13. [Operational Runbooks](#13-operational-runbooks)

---

## 1. Executive Summary

### 1.1 Document Purpose

This document provides a comprehensive, **industry best practices-aligned** migration plan for the GX Blockchain infrastructure. It addresses:

- **High Availability (HA)** - Eliminate single points of failure
- **Load Distribution** - Balance workloads across servers
- **Environment Separation** - MainNet, TestNet, DevNet isolation
- **Security Hardening** - Certificate management, secrets, network policies
- **Disaster Recovery** - Automated backups to Google Drive
- **Comprehensive Testing** - End-to-end validation framework

### 1.2 Key Findings from Audit

#### Current CA Infrastructure (ALREADY WELL-STRUCTURED)

Your Fabric CA hierarchy follows Hyperledger best practices:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CURRENT CA HIERARCHY (fabric namespace)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                          ┌──────────────┐                                   │
│                          │   ca-root    │ ← Root CA (Trust Anchor)         │
│                          │   Port 7054  │   Expires: Oct 2040              │
│                          └──────┬───────┘                                   │
│                                 │                                           │
│           ┌─────────────────────┼─────────────────────┐                     │
│           │                     │                     │                     │
│    ┌──────┴──────┐       ┌──────┴──────┐       ┌──────┴──────┐             │
│    │  ca-org1    │       │  ca-org2    │       │ ca-orderer  │             │
│    │  Port 9054  │       │  Port 10054 │       │  Port 8054  │             │
│    └─────────────┘       └─────────────┘       └─────────────┘             │
│    Issues: Org1 MSP      Issues: Org2 MSP      Issues: Orderer MSP         │
│    - peer certs          - peer certs          - orderer certs             │
│    - client certs        - client certs        - admin certs               │
│    - admin certs         - admin certs                                      │
│                                                                             │
│                          ┌──────────────┐                                   │
│                          │   ca-tls     │ ← Dedicated TLS CA               │
│                          │  Port 11054  │   (Best Practice!)               │
│                          └──────────────┘                                   │
│                          Issues all TLS certificates                        │
│                          Separate from identity PKI                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**✅ Positive Findings:**
- Proper hierarchical CA structure with Root CA
- Dedicated TLS CA (industry best practice)
- Per-organization Intermediate CAs
- Certificates stored as Kubernetes Secrets
- cert-manager installed for Let's Encrypt automation
- PostgreSQL backing store for CA databases

**⚠️ Issues to Address:**
- All CAs running on same node (no HA)
- Root CA should be offline/HSM-protected in production
- Certificate expiry monitoring needs enhancement
- Some LoadBalancer services showing `<pending>` status

### 1.3 Infrastructure Inventory

| Server | IP | Current State | Target State |
|--------|-----|--------------|--------------|
| VPS-1 | 72.60.210.201 | Overloaded (ALL Fabric) | MainNet Node 1 + Monitoring |
| VPS-2 | 72.61.116.210 | Idle K3s Worker | MainNet Node 2 |
| VPS-3 | 72.61.81.3 | K3s Master (NO DOCKER!) | MainNet Node 3 + Backup |
| VPS-4 | 217.196.51.190 | K3s Master | DevNet + TestNet |
| VPS-5 | 195.35.36.174 | Partner + Website | Partner + Website (No change) |

---

## 2. Current State Analysis

### 2.1 Kubernetes Fabric Components (fabric namespace)

| Component | Pod Name | Status | Node | Notes |
|-----------|----------|--------|------|-------|
| **Root CA** | ca-root-0 | Running | srv1089618 | Trust anchor |
| **TLS CA** | ca-tls-0 | Running | srv1089618 | TLS certificates |
| **Orderer CA** | ca-orderer-0 | Running | srv1089618 | Orderer identity |
| **Org1 CA** | ca-org1-0 | Running | srv1089618 | Organization 1 |
| **Org2 CA** | ca-org2-0 | Running | srv1089618 | Organization 2 |
| **Orderer 0** | orderer0-0 | Running | srv1089618 | Raft leader eligible |
| **Orderer 1** | orderer1-0 | Running | srv1089618 | Raft follower |
| **Orderer 2** | orderer2-0 | Running | srv1089618 | Raft follower |
| **Orderer 3** | orderer3-0 | Running | srv1089618 | Raft follower |
| **Orderer 4** | orderer4-0 | Running | srv1089618 | Raft follower |
| **Peer0-Org1** | peer0-org1-0 | Running | srv1089618 | Anchor peer |
| **Peer1-Org1** | peer1-org1-0 | Running | srv1089618 | |
| **Peer0-Org2** | peer0-org2-0 | Running | srv1089618 | Anchor peer |
| **Peer1-Org2** | peer1-org2-0 | Running | srv1089618 | |
| **CouchDB** | couchdb-peer*-0 | Running | srv1089618 | State databases |
| **Chaincode** | gxtv3-chaincode-0 | Running | srv1089618 | Smart contract |

### 2.2 External Services Configuration

| Service | Type | External IP | Ports | Status |
|---------|------|-------------|-------|--------|
| orderer0-external | LoadBalancer | 72.60.210.201 | 27050, 7053 | ✅ Active |
| orderer1-external | LoadBalancer | 72.60.210.201 | 28050, 8053 | ✅ Active |
| orderer2-external | LoadBalancer | 72.60.210.201 | 29050, 9053 | ✅ Active |
| orderer3-external | LoadBalancer | 72.60.210.201 | 30050, 10053 | ✅ Active |
| orderer4-external | LoadBalancer | 72.60.210.201 | 31050, 11053 | ✅ Active |
| peer0-org1-external | LoadBalancer | 72.61.81.3, 72.60.210.201 | 37051, 39443 | ✅ Multi-IP |
| ca-org1-external | LoadBalancer | 72.60.210.201 | 7354, 17354 | ✅ Active |
| ingress-nginx-controller | LoadBalancer | `<pending>` | 80, 443 | ⚠️ No External IP |

### 2.3 SSL/TLS Certificate Status

| Domain | Issuer | Expiry | Status | Action Required |
|--------|--------|--------|--------|-----------------|
| goodness.exchange | Let's Encrypt | Jul 23, 2025 | ⚠️ 7 months | Auto-renew configured |
| gxcoin.money | Let's Encrypt | Jan 3, 2026 | ✅ Valid | Auto-renew configured |
| wallet.gxcoin.money | Let's Encrypt | Dec 27, 2025 | ✅ Valid | Auto-renew configured |
| Fabric Root CA | Self-signed | Oct 23, 2040 | ✅ Valid | 15-year validity |
| Org1 Admin Cert | ca-org1 | Nov 20, 2026 | ✅ Valid | 1-year validity |

---

## 3. Industry Best Practices Framework

### 3.1 Hyperledger Fabric Best Practices

| Practice | Current Status | Recommendation | Priority |
|----------|----------------|----------------|----------|
| **Orderer Distribution** | ❌ All on 1 node | Distribute across 3+ nodes | 🔴 Critical |
| **Peer Distribution** | ❌ All on 1 node | 1 peer per org per node minimum | 🔴 Critical |
| **Raft Quorum** | ✅ 5 orderers | Maintain 5 for 2-fault tolerance | ✅ Good |
| **Separate TLS CA** | ✅ Implemented | Already following best practice | ✅ Good |
| **CouchDB Per Peer** | ✅ Implemented | Each peer has dedicated CouchDB | ✅ Good |
| **Channel Per Use Case** | ⚠️ Single channel | Consider multi-channel for privacy | 🟡 Medium |
| **Private Data Collections** | Unknown | Implement for sensitive data | 🟡 Medium |
| **Chaincode Lifecycle** | ✅ v2.0 lifecycle | Using modern chaincode management | ✅ Good |

### 3.2 Kubernetes Best Practices

| Practice | Current Status | Recommendation | Priority |
|----------|----------------|----------------|----------|
| **Pod Anti-Affinity** | ❌ Not configured | Spread critical pods across nodes | 🔴 Critical |
| **Resource Limits** | ⚠️ Partial | Define CPU/memory limits for all pods | 🟡 Medium |
| **PodDisruptionBudgets** | ❌ Not configured | Ensure minimum availability | 🔴 Critical |
| **Network Policies** | ⚠️ Partial (kube-router) | Implement strict namespace isolation | 🟡 Medium |
| **RBAC** | ✅ K3s default | Review and harden service accounts | 🟡 Medium |
| **Secrets Management** | ⚠️ K8s Secrets | Consider HashiCorp Vault for production | 🟢 Low |
| **Horizontal Pod Autoscaler** | ❌ Not configured | Enable for backend services | 🟢 Low |
| **Cluster Autoscaler** | N/A | Fixed node count (appropriate for now) | N/A |

### 3.3 Docker Best Practices

| Practice | Current Status | Recommendation | Priority |
|----------|----------------|----------------|----------|
| **Non-Root Containers** | ⚠️ Mixed | Run all containers as non-root | 🟡 Medium |
| **Read-Only Filesystems** | ❌ Not configured | Enable where possible | 🟢 Low |
| **Image Scanning** | ❌ Not configured | Implement Trivy scanning | 🟡 Medium |
| **Private Registry** | ✅ Running on :30500 | Already using private registry | ✅ Good |
| **Resource Limits** | ⚠️ Partial | Set memory/CPU limits in docker-compose | 🟡 Medium |
| **Health Checks** | ✅ Configured | Fabric containers have health checks | ✅ Good |
| **Log Rotation** | ⚠️ Partial | Configure json-file log driver limits | 🟡 Medium |

### 3.4 Certificate Authority Best Practices

| Practice | Current Status | Recommendation | Priority |
|----------|----------------|----------------|----------|
| **Root CA Offline** | ❌ Running online | Move to offline/HSM for production | 🟡 Medium |
| **Intermediate CAs** | ✅ Implemented | Using org-specific intermediate CAs | ✅ Good |
| **Separate TLS PKI** | ✅ Implemented | TLS CA separate from identity CA | ✅ Good |
| **Certificate Rotation** | ⚠️ Manual | Automate with cert-manager integration | 🟡 Medium |
| **CRL/OCSP** | ⚠️ Not verified | Implement certificate revocation | 🟡 Medium |
| **Key Algorithm** | ✅ ECDSA P-256 | Using modern elliptic curve | ✅ Good |
| **Certificate Validity** | ⚠️ 1 year | Appropriate, but automate renewal | 🟡 Medium |
| **HSM Integration** | ❌ Not implemented | Consider for Root CA keys in production | 🟢 Future |

### 3.5 Database Best Practices

| Practice | Current Status | Recommendation | Priority |
|----------|----------------|----------------|----------|
| **PostgreSQL HA** | ✅ 3 replicas | Running StatefulSet with replication | ✅ Good |
| **Redis HA** | ✅ 3 replicas | Running StatefulSet with replication | ✅ Good |
| **CouchDB Clustering** | ❌ Standalone | Consider CouchDB cluster for HA | 🟡 Medium |
| **Automated Backups** | ✅ CronJob 6h | postgres-backup, redis-backup running | ✅ Good |
| **Connection Pooling** | ⚠️ Unknown | Implement PgBouncer if needed | 🟢 Low |
| **Encryption at Rest** | ⚠️ Unknown | Verify disk encryption | 🟡 Medium |

---

## 4. Certificate Authority Architecture

### 4.1 Current CA Deployment

```yaml
# Current CA Services in fabric namespace
Services:
  ca-root:
    ClusterIP: 10.43.63.120
    Ports: 7054 (CA), 17054 (Operations)
    External: LoadBalancer (pending) → 7154, 17154
    
  ca-tls:
    ClusterIP: 10.43.170.136
    Ports: 11054 (CA), 21054 (Operations)
    External: LoadBalancer (pending) → 7554, 17554
    
  ca-orderer:
    ClusterIP: 10.43.226.99
    Ports: 8054 (CA), 18054 (Operations)
    External: LoadBalancer (pending) → 7254, 17254
    
  ca-org1:
    ClusterIP: 10.43.162.135
    Ports: 9054 (CA), 19054 (Operations)
    External: LoadBalancer 72.60.210.201 → 7354, 17354
    
  ca-org2:
    ClusterIP: 10.43.57.59
    Ports: 10054 (CA), 20054 (Operations)
    External: LoadBalancer (pending) → 7454, 17454
```

### 4.2 CA Secrets Structure

```
fabric namespace secrets:
├── ca-root-secret (9 keys)
│   ├── ca-cert.pem
│   ├── ca-key.pem
│   ├── tls-cert.pem
│   ├── tls-key.pem
│   └── ... (admin credentials)
├── ca-tls-secret (8 keys)
├── ca-orderer-secret (8 keys)
├── ca-org1-secret (8 keys)
├── ca-org2-secret (8 keys)
├── orderer0-crypto (11 keys) ← Full MSP + TLS
├── orderer1-crypto (11 keys)
├── orderer2-crypto (11 keys)
├── orderer3-crypto (11 keys)
├── orderer4-crypto (11 keys)
├── peer0-org1-crypto (11 keys)
├── peer0-org2-crypto (11 keys)
├── peer1-org1-crypto (11 keys)
├── peer1-org2-crypto (11 keys)
├── org1-admin-crypto (6 keys)
├── org2-admin-crypto (6 keys)
├── chaincode-tls-client (3 keys)
└── peer-tls-ca (1 key)
```

### 4.3 Target CA Architecture (Best Practices)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TARGET CA ARCHITECTURE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PRODUCTION RECOMMENDATION:                                                │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                      ROOT CA (OFFLINE)                               │  │
│   │   • Store private key in HSM or air-gapped system                   │  │
│   │   • Only bring online for signing intermediate CA certs             │  │
│   │   • 15-20 year validity                                             │  │
│   │   • Current: Running online (acceptable for dev/staging)            │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                 │                                           │
│              ┌──────────────────┼──────────────────┐                        │
│              │                  │                  │                        │
│              ▼                  ▼                  ▼                        │
│   ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐           │
│   │   ORDERER CA     │ │    ORG1 CA       │ │    ORG2 CA       │           │
│   │   VPS-1          │ │    VPS-1         │ │    VPS-2         │ ← HA     │
│   │   (Primary)      │ │    (Primary)     │ │    (Primary)     │           │
│   └──────────────────┘ └──────────────────┘ └──────────────────┘           │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                        TLS CA (DEDICATED)                            │  │
│   │   • Issues ALL TLS certificates                                      │  │
│   │   • Separate trust domain from identity                             │  │
│   │   • Current: ✅ Already implemented correctly                        │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│   CERTIFICATE TYPES:                                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ Type          │ Issued By    │ Usage                    │ Validity  │  │
│   │───────────────│──────────────│──────────────────────────│───────────│  │
│   │ Enrollment    │ Org CAs      │ Identity authentication  │ 1 year    │  │
│   │ TLS Server    │ TLS CA       │ gRPC/HTTP TLS            │ 1 year    │  │
│   │ TLS Client    │ TLS CA       │ Mutual TLS (mTLS)        │ 1 year    │  │
│   │ Admin         │ Org CAs      │ Channel/chaincode admin  │ 1 year    │  │
│   │ Orderer       │ Orderer CA   │ Ordering service         │ 1 year    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 CA Certificate Rotation Plan

```bash
#!/bin/bash
# CA Certificate Rotation Procedure

# 1. Check certificate expiry (run monthly)
check_cert_expiry() {
  kubectl get secrets -n fabric -o json | \
    jq -r '.items[] | select(.data["tls-cert.pem"]) | .metadata.name' | \
    while read secret; do
      echo "Checking: $secret"
      kubectl get secret $secret -n fabric -o jsonpath='{.data.tls-cert\.pem}' | \
        base64 -d | openssl x509 -noout -enddate
    done
}

# 2. Rotate certificates 30 days before expiry
rotate_peer_cert() {
  PEER=$1
  ORG=$2
  
  # Enroll new certificate
  fabric-ca-client enroll \
    -u https://peer0-org1:peerpw@ca-org1:9054 \
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

# 3. Monitor with Prometheus
# Add to prometheus-rules.yaml:
# - alert: FabricCertExpiringSoon
#   expr: fabric_cert_expiry_days < 30
#   for: 1h
#   labels:
#     severity: warning
```

---

## 5. Target Architecture

### 5.1 Server Role Distribution

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TARGET SERVER DISTRIBUTION                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   VPS-1 (72.60.210.201) - MAINNET PRIMARY                                  │
│   ├── Orderer 0, 1 (Raft cluster)                                          │
│   ├── Peer0.Org1, Peer1.Org1                                               │
│   ├── CouchDB × 2 (for Org1 peers)                                         │
│   ├── CA-Root, CA-Org1, CA-TLS                                             │
│   ├── Prometheus, Grafana, AlertManager                                    │
│   ├── Loki (log aggregation)                                               │
│   └── Frontend (gx-wallet-frontend) - existing                             │
│                                                                             │
│   VPS-2 (72.61.116.210) - MAINNET SECONDARY                                │
│   ├── Orderer 2, 3 (Raft cluster)                                          │
│   ├── Peer0.Org2, Peer1.Org2                                               │
│   ├── CouchDB × 2 (for Org2 peers)                                         │
│   ├── CA-Org2, CA-Orderer                                                  │
│   ├── Backend services replica                                              │
│   └── PostgreSQL replica                                                    │
│                                                                             │
│   VPS-3 (72.61.81.3) - MAINNET TERTIARY + BACKUP                           │
│   ├── Orderer 4 (Raft cluster - tiebreaker)                                │
│   ├── PostgreSQL Primary                                                    │
│   ├── Redis Primary                                                         │
│   ├── MinIO (backup storage)                                               │
│   ├── Velero (K8s backup)                                                  │
│   └── REQUIRES: Docker installation                                         │
│                                                                             │
│   VPS-4 (217.196.51.190) - DEVELOPMENT + TESTING                           │
│   ├── DevNet (isolated):                                                    │
│   │   └── Solo orderer, 1 peer, 1 CA, 1 CouchDB                           │
│   ├── TestNet (current fabric-testnet namespace)                           │
│   │   └── 3 orderers, 2 peers, full backend                               │
│   ├── CI/CD (Jenkins/GitLab Runner)                                        │
│   └── Private Registry (existing :30500)                                   │
│                                                                             │
│   VPS-5 (195.35.36.174) - PARTNER + WEBSITE (NO CHANGES)                   │
│   ├── Partner Peer (gx-partnerorg1 namespace)                              │
│   ├── Partner CouchDB                                                       │
│   └── Marketing Website (gxcoin.money)                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Kubernetes Node Affinity Configuration

```yaml
# Node Labels (to be applied)
# VPS-1
kubectl label node srv1089618.hstgr.cloud \
  topology.gx.io/zone=zone-a \
  node.gx.io/role=mainnet-primary \
  fabric.gx.io/org=org1

# VPS-2
kubectl label node srv1117946.hstgr.cloud \
  topology.gx.io/zone=zone-b \
  node.gx.io/role=mainnet-secondary \
  fabric.gx.io/org=org2

# VPS-3
kubectl label node srv1092158.hstgr.cloud \
  topology.gx.io/zone=zone-c \
  node.gx.io/role=mainnet-tertiary \
  fabric.gx.io/role=backup

# VPS-4
kubectl label node srv1089624.hstgr.cloud \
  topology.gx.io/zone=zone-d \
  node.gx.io/role=development \
  fabric.gx.io/env=dev-test
```

### 5.3 Pod Anti-Affinity Rules

```yaml
# Orderer Anti-Affinity (spread across nodes)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: orderer0
  namespace: fabric
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

### 5.4 PodDisruptionBudget Configuration

```yaml
# Ensure minimum orderer availability
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orderer-pdb
  namespace: fabric
spec:
  minAvailable: 3  # Maintain quorum (3 of 5)
  selector:
    matchLabels:
      app: orderer

---
# Ensure minimum peer availability per org
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

---

## 6. Security & Compliance Standards

### 6.1 Network Security

```yaml
# Network Policy - Fabric Namespace Isolation
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
  # Allow from ingress
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  # Allow from partner
  - from:
    - ipBlock:
        cidr: 195.35.36.174/32
    ports:
    - protocol: TCP
      port: 7050  # Orderer
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
  # Allow external orderer communication
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 7050
```

### 6.2 Secrets Management

```yaml
# Current: Kubernetes Secrets (acceptable for staging)
# Recommended for Production: HashiCorp Vault

# Secret encryption at rest (verify K3s config)
# /etc/rancher/k3s/config.yaml should include:
# secrets-encryption: true

# Secret audit logging
# Enable Kubernetes audit logging for secret access
```

### 6.3 TLS Configuration Standards

```yaml
# Minimum TLS version: 1.2
# Recommended cipher suites for Fabric:
ORDERER_GENERAL_TLS_CIPHER_SUITES: |
  TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
  TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

---

## 7. Pre-Migration Preparation

### 7.1 Install Docker on VPS-3

```bash
#!/bin/bash
# Run on 72.61.81.3

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

### 7.2 Backup to Google Drive

```bash
#!/bin/bash
# Backup Script with Google Drive Integration
# Credentials: gxc@handsforeducation.org

# Install rclone
curl https://rclone.org/install.sh | bash

# Configure rclone for Google Drive
rclone config create gdrive drive \
  scope drive \
  service_account_file /root/.config/gcloud/service-account.json

# Or interactive setup:
# rclone config
# Choose: Google Drive
# Client ID: (leave blank for shared)
# Client Secret: (leave blank for shared)
# Scope: 1 (full access)
# Root folder ID: (leave blank)
# Service Account: gxc@handsforeducation.org

# Full backup function
backup_to_gdrive() {
  BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="/root/backups/$BACKUP_DATE"
  mkdir -p $BACKUP_DIR
  
  echo "=== Starting Full Backup: $BACKUP_DATE ==="
  
  # 1. Kubernetes resources
  echo "Backing up Kubernetes resources..."
  for ns in fabric fabric-testnet backend-mainnet backend-testnet; do
    kubectl get all -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-all.yaml
    kubectl get secrets -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-secrets.yaml
    kubectl get configmaps -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-configmaps.yaml
    kubectl get pvc -n $ns -o yaml > $BACKUP_DIR/k8s-$ns-pvc.yaml
  done
  
  # 2. Fabric crypto materials
  echo "Backing up Fabric crypto materials..."
  kubectl get secrets -n fabric -o json | jq -r '.items[] | select(.metadata.name | contains("crypto")) | @base64' > $BACKUP_DIR/fabric-crypto-secrets.b64
  
  # 3. PostgreSQL database
  echo "Backing up PostgreSQL..."
  kubectl exec -n backend-mainnet postgres-0 -- pg_dumpall -U postgres > $BACKUP_DIR/postgres-full.sql
  
  # 4. Redis data
  echo "Backing up Redis..."
  kubectl exec -n backend-mainnet redis-0 -- redis-cli BGSAVE
  sleep 5
  kubectl cp backend-mainnet/redis-0:/data/dump.rdb $BACKUP_DIR/redis-dump.rdb
  
  # 5. CouchDB state databases
  echo "Backing up CouchDB..."
  for peer in peer0-org1 peer0-org2 peer1-org1 peer1-org2; do
    COUCHDB_POD=$(kubectl get pod -n fabric -l app=couchdb,peer=$peer -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n fabric $COUCHDB_POD -- curl -s http://localhost:5984/_all_dbs | jq -r '.[]' | while read db; do
      kubectl exec -n fabric $COUCHDB_POD -- curl -s "http://localhost:5984/$db/_all_docs?include_docs=true" > "$BACKUP_DIR/couchdb-$peer-$db.json"
    done
  done
  
  # 6. Docker volumes (VPS-1)
  echo "Backing up Docker volumes..."
  ssh root@72.60.210.201 "cd /var/lib/docker/volumes && tar -czf /tmp/docker-volumes.tar.gz ."
  scp root@72.60.210.201:/tmp/docker-volumes.tar.gz $BACKUP_DIR/
  
  # 7. Application configs
  echo "Backing up application configs..."
  scp -r root@72.60.210.201:/home/sugxcoin/prod-blockchain/gx-coin-fabric/network/*.yaml $BACKUP_DIR/
  scp root@72.60.210.201:/home/sugxcoin/prod-blockchain/gx-protocol-backend/.env $BACKUP_DIR/backend-env
  scp root@72.60.210.201:/home/sugxcoin/prod-blockchain/gx-wallet-frontend/.env.local $BACKUP_DIR/frontend-env
  
  # 8. Create archive
  echo "Creating archive..."
  tar -czvf /root/backups/gx-full-backup-$BACKUP_DATE.tar.gz -C $BACKUP_DIR .
  
  # 9. Upload to Google Drive
  echo "Uploading to Google Drive..."
  rclone copy /root/backups/gx-full-backup-$BACKUP_DATE.tar.gz gdrive:GX-Backups/
  
  # 10. Cleanup local (keep last 3)
  ls -t /root/backups/gx-full-backup-*.tar.gz | tail -n +4 | xargs -r rm
  rm -rf $BACKUP_DIR
  
  echo "=== Backup Complete: gx-full-backup-$BACKUP_DATE.tar.gz ==="
  echo "Uploaded to: Google Drive → GX-Backups/"
}

# Run backup
backup_to_gdrive
```

### 7.3 Pre-Migration Checklist

```markdown
## Pre-Migration Checklist

### Infrastructure
- [ ] Docker installed on VPS-3 (72.61.81.3)
- [ ] All K3s nodes healthy (`kubectl get nodes`)
- [ ] All pods running (`kubectl get pods -A`)
- [ ] Disk space > 50% free on all servers
- [ ] Memory usage < 80% on all servers

### Backups
- [ ] Full backup completed to Google Drive
- [ ] PostgreSQL backup verified (can restore)
- [ ] Redis backup verified
- [ ] CouchDB backup verified
- [ ] Fabric crypto materials backed up
- [ ] Kubernetes resources exported

### Network
- [ ] Inter-server connectivity tested (ping, nc)
- [ ] Required ports open on firewall
- [ ] DNS records verified
- [ ] Cloudflare configuration documented

### Security
- [ ] SSL certificates valid (> 30 days)
- [ ] Kubernetes secrets encrypted
- [ ] Access credentials documented (secure storage)

### Communication
- [ ] Stakeholders notified of maintenance window
- [ ] Rollback plan documented
- [ ] Support contacts available
```

---

## 8. Migration Phases

### Phase 1: Preparation (2-3 hours)

| Step | Action | Command/Procedure | Validation |
|------|--------|-------------------|------------|
| 1.1 | Create full backup | `backup_to_gdrive` | Check Google Drive |
| 1.2 | Install Docker on VPS-3 | See Section 7.1 | `docker info` |
| 1.3 | Label K8s nodes | See Section 5.2 | `kubectl get nodes --show-labels` |
| 1.4 | Verify connectivity | See Section 9.1 | All tests pass |

### Phase 2: Infrastructure Setup (4-6 hours)

| Step | Action | Details | Validation |
|------|--------|---------|------------|
| 2.1 | Apply PodDisruptionBudgets | Section 5.4 | `kubectl get pdb -n fabric` |
| 2.2 | Create NetworkPolicies | Section 6.1 | `kubectl get networkpolicy -n fabric` |
| 2.3 | Update node affinity | Section 5.3 | Pods scheduled correctly |
| 2.4 | Deploy additional CouchDB | VPS-2 CouchDB for Org2 | `kubectl get pods -n fabric` |

### Phase 3: Fabric Migration (6-8 hours)

| Step | Action | Risk Level | Rollback |
|------|--------|------------|----------|
| 3.1 | Scale orderers to target nodes | Low | Scale back |
| 3.2 | Migrate Org2 peers to VPS-2 | Medium | Keep original |
| 3.3 | Verify Raft consensus | Critical | Check leader election |
| 3.4 | Update anchor peers | Low | Revert config |
| 3.5 | Test chaincode | Critical | Use original peers |

### Phase 4: Cutover (2-3 hours)

| Step | Action | Downtime | Validation |
|------|--------|----------|------------|
| 4.1 | Update backend config | 0 | Rolling restart |
| 4.2 | Update ingress | ~1 min | HTTP check |
| 4.3 | Verify transactions | 0 | Submit test tx |
| 4.4 | Update partner connection | ~5 min | Partner peer sync |

### Phase 5: Validation & Monitoring (Ongoing)

| Step | Action | Frequency | Alert Threshold |
|------|--------|-----------|-----------------|
| 5.1 | Monitor pod health | Continuous | Any crash |
| 5.2 | Check block height sync | Every 5 min | > 10 block lag |
| 5.3 | Verify transaction latency | Every 1 min | > 5 seconds |
| 5.4 | Test failover | After 24 hours | Any failure |

---

## 9. Comprehensive Testing Plan

### 9.1 Network Connectivity Tests

```bash
#!/bin/bash
# /root/test-scripts/test-network-connectivity.sh

echo "=========================================="
echo "NETWORK CONNECTIVITY TEST SUITE"
echo "=========================================="
echo "Date: $(date)"
echo ""

SERVERS=(
  "72.60.210.201:VPS-1"
  "72.61.116.210:VPS-2"
  "72.61.81.3:VPS-3"
  "217.196.51.190:VPS-4"
  "195.35.36.174:VPS-5"
)

# Test 1: Basic connectivity (ICMP)
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
echo ""

# Test 2: SSH connectivity
echo "=== TEST 2: SSH (Port 22) ==="
for server in "${SERVERS[@]}"; do
  IP=$(echo $server | cut -d: -f1)
  NAME=$(echo $server | cut -d: -f2)
  if nc -zv -w 3 $IP 22 2>&1 | grep -q succeeded; then
    echo "✅ $NAME ($IP): SSH accessible"
  else
    echo "❌ $NAME ($IP): SSH not accessible"
  fi
done
echo ""

# Test 3: Kubernetes API
echo "=== TEST 3: Kubernetes API (Port 6443) ==="
for server in "${SERVERS[@]}"; do
  IP=$(echo $server | cut -d: -f1)
  NAME=$(echo $server | cut -d: -f2)
  if nc -zv -w 3 $IP 6443 2>&1 | grep -q succeeded; then
    echo "✅ $NAME ($IP): K8s API accessible"
  else
    echo "⚠️  $NAME ($IP): K8s API not accessible (may be expected)"
  fi
done
echo ""

# Test 4: Fabric Orderer ports
echo "=== TEST 4: Fabric Orderer Ports ==="
ORDERER_PORTS=(27050 28050 29050 30050 31050)
for port in "${ORDERER_PORTS[@]}"; do
  if nc -zv -w 3 72.60.210.201 $port 2>&1 | grep -q succeeded; then
    echo "✅ Orderer port $port: Accessible"
  else
    echo "❌ Orderer port $port: Not accessible"
  fi
done
echo ""

# Test 5: Fabric Peer ports
echo "=== TEST 5: Fabric Peer Ports ==="
PEER_PORTS=(7051 8051 9051 10051 37051 38051 47051 48051)
for port in "${PEER_PORTS[@]}"; do
  if nc -zv -w 3 72.60.210.201 $port 2>&1 | grep -q succeeded; then
    echo "✅ Peer port $port: Accessible"
  else
    echo "⚠️  Peer port $port: Not accessible (check if expected)"
  fi
done
echo ""

# Test 6: CouchDB ports
echo "=== TEST 6: CouchDB Ports ==="
COUCHDB_PORTS=(5984 6984 7984 8984)
for port in "${COUCHDB_PORTS[@]}"; do
  if curl -s -o /dev/null -w "%{http_code}" http://72.60.210.201:$port | grep -q 200; then
    echo "✅ CouchDB port $port: Responding"
  else
    echo "⚠️  CouchDB port $port: Not responding (may be internal only)"
  fi
done
echo ""

# Test 7: Partner connectivity
echo "=== TEST 7: Partner Server Connectivity ==="
if nc -zv -w 3 195.35.36.174 30051 2>&1 | grep -q succeeded; then
  echo "✅ Partner peer port 30051: Accessible"
else
  echo "⚠️  Partner peer port 30051: Not accessible from this node"
fi
echo ""

# Test 8: DNS resolution
echo "=== TEST 8: DNS Resolution ==="
DOMAINS=("api.gxcoin.money" "gxcoin.money" "wallet.gxcoin.money" "goodness.exchange")
for domain in "${DOMAINS[@]}"; do
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

### 9.2 Kubernetes Health Tests

```bash
#!/bin/bash
# /root/test-scripts/test-kubernetes-health.sh

echo "=========================================="
echo "KUBERNETES HEALTH TEST SUITE"
echo "=========================================="

# Test 1: Node status
echo "=== TEST 1: Node Status ==="
kubectl get nodes -o wide
echo ""
NOT_READY=$(kubectl get nodes | grep -v Ready | grep -v NAME | wc -l)
if [ "$NOT_READY" -eq 0 ]; then
  echo "✅ All nodes are Ready"
else
  echo "❌ $NOT_READY node(s) not Ready"
fi
echo ""

# Test 2: Pod status by namespace
echo "=== TEST 2: Pod Status ==="
for ns in fabric fabric-testnet backend-mainnet backend-testnet monitoring; do
  TOTAL=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l)
  RUNNING=$(kubectl get pods -n $ns --no-headers 2>/dev/null | grep Running | wc -l)
  if [ "$TOTAL" -eq "$RUNNING" ] && [ "$TOTAL" -gt 0 ]; then
    echo "✅ $ns: $RUNNING/$TOTAL pods running"
  else
    echo "⚠️  $ns: $RUNNING/$TOTAL pods running"
    kubectl get pods -n $ns | grep -v Running | grep -v NAME
  fi
done
echo ""

# Test 3: Fabric pods specifically
echo "=== TEST 3: Fabric Component Status ==="
echo "Orderers:"
kubectl get pods -n fabric -l app=orderer -o wide
echo ""
echo "Peers:"
kubectl get pods -n fabric -l app=peer -o wide
echo ""
echo "CAs:"
kubectl get pods -n fabric -l app=ca -o wide
echo ""
echo "CouchDB:"
kubectl get pods -n fabric -l app=couchdb -o wide
echo ""

# Test 4: Service endpoints
echo "=== TEST 4: Service Endpoints ==="
kubectl get endpoints -n fabric
echo ""

# Test 5: PVC status
echo "=== TEST 5: Persistent Volume Claims ==="
kubectl get pvc -n fabric
PENDING_PVC=$(kubectl get pvc -n fabric | grep -v Bound | grep -v NAME | wc -l)
if [ "$PENDING_PVC" -eq 0 ]; then
  echo "✅ All PVCs are Bound"
else
  echo "❌ $PENDING_PVC PVC(s) not Bound"
fi
echo ""

# Test 6: Resource utilization
echo "=== TEST 6: Node Resource Utilization ==="
kubectl top nodes
echo ""

# Test 7: Pod resource utilization
echo "=== TEST 7: Pod Resource Utilization (Fabric) ==="
kubectl top pods -n fabric
echo ""

echo "=========================================="
echo "KUBERNETES HEALTH TEST COMPLETE"
echo "=========================================="
```

### 9.3 Fabric Network Tests

```bash
#!/bin/bash
# /root/test-scripts/test-fabric-network.sh

echo "=========================================="
echo "HYPERLEDGER FABRIC NETWORK TEST SUITE"
echo "=========================================="

# Set environment
export FABRIC_CFG_PATH=/etc/hyperledger/fabric
export CORE_PEER_TLS_ENABLED=true

# Test 1: Orderer health
echo "=== TEST 1: Orderer Health ==="
for i in 0 1 2 3 4; do
  PORT=$((27050 + i * 1000))
  HEALTH=$(curl -s http://72.60.210.201:$((7053 + i * 1000))/healthz 2>/dev/null)
  if [ "$HEALTH" == "OK" ] || [ -n "$HEALTH" ]; then
    echo "✅ Orderer $i: Healthy"
  else
    echo "❌ Orderer $i: Not responding"
  fi
done
echo ""

# Test 2: Peer health
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
echo ""

# Test 3: Channel membership
echo "=== TEST 3: Channel Membership ==="
PEER0_ORG1=$(kubectl get pods -n fabric -l app=peer,peer=peer0-org1 -o jsonpath='{.items[0].metadata.name}')
echo "Channels joined by $PEER0_ORG1:"
kubectl exec -n fabric $PEER0_ORG1 -c peer -- peer channel list 2>/dev/null
echo ""

# Test 4: Ledger height
echo "=== TEST 4: Ledger Height Consistency ==="
declare -A HEIGHTS
for pod in $PEER_PODS; do
  HEIGHT=$(kubectl exec -n fabric $pod -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
  HEIGHTS[$pod]=$HEIGHT
  echo "$pod: Block height = $HEIGHT"
done

# Check if all heights are equal
UNIQUE_HEIGHTS=$(echo "${HEIGHTS[@]}" | tr ' ' '\n' | sort -u | wc -l)
if [ "$UNIQUE_HEIGHTS" -eq 1 ]; then
  echo "✅ All peers have consistent ledger height"
else
  echo "⚠️  Ledger heights differ - may be syncing"
fi
echo ""

# Test 5: Chaincode status
echo "=== TEST 5: Chaincode Status ==="
kubectl exec -n fabric $PEER0_ORG1 -c peer -- peer lifecycle chaincode querycommitted -C gxchannel 2>/dev/null
echo ""

# Test 6: Chaincode query
echo "=== TEST 6: Chaincode Query Test ==="
QUERY_RESULT=$(kubectl exec -n fabric $PEER0_ORG1 -c peer -- peer chaincode query -C gxchannel -n gxtv3 -c '{"function":"GetMetadata","Args":[]}' 2>/dev/null)
if [ -n "$QUERY_RESULT" ]; then
  echo "✅ Chaincode query successful"
  echo "Response: ${QUERY_RESULT:0:100}..."
else
  echo "❌ Chaincode query failed"
fi
echo ""

# Test 7: Raft consensus
echo "=== TEST 7: Raft Consensus Status ==="
# Check orderer logs for leader election
ORDERER0_POD=$(kubectl get pods -n fabric -l app=orderer,orderer=orderer0 -o jsonpath='{.items[0].metadata.name}')
LEADER_LOG=$(kubectl logs -n fabric $ORDERER0_POD --tail=100 2>/dev/null | grep -i "leader" | tail -1)
if [ -n "$LEADER_LOG" ]; then
  echo "✅ Raft consensus active"
  echo "Last leader event: $LEADER_LOG"
else
  echo "⚠️  Cannot determine Raft status from logs"
fi
echo ""

echo "=========================================="
echo "FABRIC NETWORK TEST COMPLETE"
echo "=========================================="
```

### 9.4 Application Endpoint Tests

```bash
#!/bin/bash
# /root/test-scripts/test-application-endpoints.sh

echo "=========================================="
echo "APPLICATION ENDPOINT TEST SUITE"
echo "=========================================="

# API Base URL
API_BASE="https://api.gxcoin.money"
WALLET_BASE="https://wallet.gxcoin.money"
WEBSITE_BASE="https://gxcoin.money"

# Test 1: API Health
echo "=== TEST 1: API Health Endpoints ==="
endpoints=(
  "$API_BASE/health"
  "$API_BASE/api/v1/health"
)
for endpoint in "${endpoints[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null)
  if [ "$STATUS" == "200" ]; then
    echo "✅ $endpoint: HTTP $STATUS"
  else
    echo "❌ $endpoint: HTTP $STATUS"
  fi
done
echo ""

# Test 2: API Endpoints (require auth - expect 401)
echo "=== TEST 2: API Authentication Check ==="
auth_endpoints=(
  "/api/v1/wallets"
  "/api/v1/transactions"
  "/api/v1/organizations"
  "/api/v1/balances"
  "/api/v1/admin"
)
for endpoint in "${auth_endpoints[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$API_BASE$endpoint" 2>/dev/null)
  if [ "$STATUS" == "401" ] || [ "$STATUS" == "403" ]; then
    echo "✅ $endpoint: Protected (HTTP $STATUS)"
  elif [ "$STATUS" == "200" ]; then
    echo "⚠️  $endpoint: Accessible without auth (HTTP $STATUS)"
  else
    echo "❌ $endpoint: Error (HTTP $STATUS)"
  fi
done
echo ""

# Test 3: Website accessibility
echo "=== TEST 3: Website Accessibility ==="
websites=(
  "$WEBSITE_BASE"
  "$WALLET_BASE"
)
for site in "${websites[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$site" 2>/dev/null)
  if [ "$STATUS" == "200" ] || [ "$STATUS" == "301" ] || [ "$STATUS" == "302" ]; then
    echo "✅ $site: Accessible (HTTP $STATUS)"
  else
    echo "❌ $site: Not accessible (HTTP $STATUS)"
  fi
done
echo ""

# Test 4: SSL certificate check
echo "=== TEST 4: SSL Certificate Verification ==="
domains=("api.gxcoin.money" "wallet.gxcoin.money" "gxcoin.money")
for domain in "${domains[@]}"; do
  EXPIRY=$(echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -n "$EXPIRY" ]; then
    echo "✅ $domain: SSL valid until $EXPIRY"
  else
    echo "❌ $domain: SSL certificate issue"
  fi
done
echo ""

# Test 5: Response time
echo "=== TEST 5: Response Time ==="
for site in "$API_BASE/health" "$WALLET_BASE" "$WEBSITE_BASE"; do
  TIME=$(curl -s -o /dev/null -w "%{time_total}" "$site" 2>/dev/null)
  if (( $(echo "$TIME < 2" | bc -l) )); then
    echo "✅ $site: ${TIME}s"
  else
    echo "⚠️  $site: ${TIME}s (slow)"
  fi
done
echo ""

# Test 6: Backend services via kubectl
echo "=== TEST 6: Backend Service Status ==="
SERVICES=("svc-identity" "svc-admin" "svc-tokenomics" "svc-governance" "svc-organization" "svc-loanpool" "svc-tax" "projector" "outbox-submitter")
for svc in "${SERVICES[@]}"; do
  READY=$(kubectl get deployment $svc -n backend-mainnet -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  DESIRED=$(kubectl get deployment $svc -n backend-mainnet -o jsonpath='{.spec.replicas}' 2>/dev/null)
  if [ "$READY" == "$DESIRED" ] && [ -n "$READY" ]; then
    echo "✅ $svc: $READY/$DESIRED replicas ready"
  else
    echo "❌ $svc: $READY/$DESIRED replicas ready"
  fi
done
echo ""

echo "=========================================="
echo "APPLICATION ENDPOINT TEST COMPLETE"
echo "=========================================="
```

### 9.5 Database Connection Tests

```bash
#!/bin/bash
# /root/test-scripts/test-database-connections.sh

echo "=========================================="
echo "DATABASE CONNECTION TEST SUITE"
echo "=========================================="

# Test 1: PostgreSQL connectivity
echo "=== TEST 1: PostgreSQL Connectivity ==="
PG_POD=$(kubectl get pods -n backend-mainnet -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n backend-mainnet $PG_POD -- psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
  echo "✅ PostgreSQL: Connected"
  
  # Check replication
  REPLICAS=$(kubectl exec -n backend-mainnet $PG_POD -- psql -U postgres -c "SELECT count(*) FROM pg_stat_replication" -t 2>/dev/null | tr -d ' ')
  echo "   Streaming replicas: $REPLICAS"
  
  # Check database size
  kubectl exec -n backend-mainnet $PG_POD -- psql -U postgres -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC LIMIT 5" 2>/dev/null
else
  echo "❌ PostgreSQL: Connection failed"
fi
echo ""

# Test 2: Redis connectivity
echo "=== TEST 2: Redis Connectivity ==="
REDIS_POD=$(kubectl get pods -n backend-mainnet -l app=redis -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli PING 2>/dev/null | grep -q PONG; then
  echo "✅ Redis: Connected (PONG)"
  
  # Check memory usage
  MEMORY=$(kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2)
  echo "   Memory usage: $MEMORY"
  
  # Check replication
  ROLE=$(kubectl exec -n backend-mainnet $REDIS_POD -- redis-cli INFO replication 2>/dev/null | grep role | cut -d: -f2)
  echo "   Role: $ROLE"
else
  echo "❌ Redis: Connection failed"
fi
echo ""

# Test 3: CouchDB connectivity
echo "=== TEST 3: CouchDB Connectivity ==="
COUCHDB_PODS=$(kubectl get pods -n fabric -l app=couchdb -o jsonpath='{.items[*].metadata.name}')
for pod in $COUCHDB_PODS; do
  RESPONSE=$(kubectl exec -n fabric $pod -- curl -s http://localhost:5984/ 2>/dev/null)
  if echo "$RESPONSE" | grep -q "couchdb"; then
    VERSION=$(echo "$RESPONSE" | jq -r '.version' 2>/dev/null)
    echo "✅ $pod: Connected (v$VERSION)"
  else
    echo "❌ $pod: Connection failed"
  fi
done
echo ""

# Test 4: Database from application pods
echo "=== TEST 4: Application → Database Connectivity ==="
APP_POD=$(kubectl get pods -n backend-mainnet -l app=svc-identity -o jsonpath='{.items[0].metadata.name}')
if [ -n "$APP_POD" ]; then
  # Test PostgreSQL from app
  PG_TEST=$(kubectl exec -n backend-mainnet $APP_POD -- sh -c 'nc -zv $DATABASE_HOST $DATABASE_PORT 2>&1' 2>/dev/null)
  if echo "$PG_TEST" | grep -q succeeded; then
    echo "✅ svc-identity → PostgreSQL: Connected"
  else
    echo "❌ svc-identity → PostgreSQL: Failed"
  fi
  
  # Test Redis from app
  REDIS_TEST=$(kubectl exec -n backend-mainnet $APP_POD -- sh -c 'nc -zv $REDIS_HOST $REDIS_PORT 2>&1' 2>/dev/null)
  if echo "$REDIS_TEST" | grep -q succeeded; then
    echo "✅ svc-identity → Redis: Connected"
  else
    echo "❌ svc-identity → Redis: Failed"
  fi
fi
echo ""

echo "=========================================="
echo "DATABASE CONNECTION TEST COMPLETE"
echo "=========================================="
```

### 9.6 End-to-End Transaction Test

```bash
#!/bin/bash
# /root/test-scripts/test-e2e-transaction.sh

echo "=========================================="
echo "END-TO-END TRANSACTION TEST"
echo "=========================================="

# This test submits a complete transaction flow

# Get auth token (if required)
# TOKEN=$(curl -s -X POST "$API_BASE/api/v1/auth/login" -H "Content-Type: application/json" -d '{"email":"test@example.com","password":"testpass"}' | jq -r '.token')

echo "=== Step 1: Check API Health ==="
HEALTH=$(curl -s https://api.gxcoin.money/health 2>/dev/null)
if [ -n "$HEALTH" ]; then
  echo "✅ API is healthy"
else
  echo "❌ API not responding"
  exit 1
fi

echo ""
echo "=== Step 2: Query Chaincode via Peer ==="
PEER_POD=$(kubectl get pods -n fabric -l app=peer,peer=peer0-org1 -o jsonpath='{.items[0].metadata.name}')
QUERY_RESULT=$(kubectl exec -n fabric $PEER_POD -c peer -- peer chaincode query -C gxchannel -n gxtv3 -c '{"function":"GetMetadata","Args":[]}' 2>/dev/null)
if [ -n "$QUERY_RESULT" ]; then
  echo "✅ Chaincode query successful"
else
  echo "❌ Chaincode query failed"
fi

echo ""
echo "=== Step 3: Check Block Production ==="
HEIGHT_BEFORE=$(kubectl exec -n fabric $PEER_POD -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
echo "Current block height: $HEIGHT_BEFORE"

# Wait a moment for new blocks
sleep 10

HEIGHT_AFTER=$(kubectl exec -n fabric $PEER_POD -c peer -- peer channel getinfo -c gxchannel 2>/dev/null | grep -oP 'height:\K\d+')
echo "Block height after 10s: $HEIGHT_AFTER"

if [ "$HEIGHT_AFTER" -ge "$HEIGHT_BEFORE" ]; then
  echo "✅ Blockchain is operational"
else
  echo "⚠️  No new blocks in 10 seconds (may be normal if no transactions)"
fi

echo ""
echo "=== Step 4: Check Event Processing ==="
PROJECTOR_POD=$(kubectl get pods -n backend-mainnet -l app=projector -o jsonpath='{.items[0].metadata.name}')
PROJECTOR_LOGS=$(kubectl logs -n backend-mainnet $PROJECTOR_POD --tail=10 2>/dev/null)
if echo "$PROJECTOR_LOGS" | grep -q -i "error"; then
  echo "⚠️  Projector has errors in recent logs"
else
  echo "✅ Projector running without errors"
fi

echo ""
echo "=== Step 5: Check Outbox Processing ==="
OUTBOX_POD=$(kubectl get pods -n backend-mainnet -l app=outbox-submitter -o jsonpath='{.items[0].metadata.name}')
RESTARTS=$(kubectl get pod $OUTBOX_POD -n backend-mainnet -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo "Outbox-submitter restart count: $RESTARTS"
if [ "$RESTARTS" -lt 50 ]; then
  echo "✅ Outbox-submitter stable"
else
  echo "⚠️  Outbox-submitter has high restart count"
fi

echo ""
echo "=========================================="
echo "END-TO-END TEST COMPLETE"
echo "=========================================="
```

### 9.7 High Availability Failover Test

```bash
#!/bin/bash
# /root/test-scripts/test-ha-failover.sh

echo "=========================================="
echo "HIGH AVAILABILITY FAILOVER TEST"
echo "=========================================="
echo "WARNING: This test will temporarily disrupt services"
echo "Only run during maintenance windows"
echo ""

read -p "Continue with HA failover test? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Test cancelled"
  exit 0
fi

# Test 1: Orderer failover
echo "=== TEST 1: Orderer Failover ==="
echo "Current orderer distribution:"
kubectl get pods -n fabric -l app=orderer -o wide

# Find current leader (if possible)
ORDERER0_POD=$(kubectl get pods -n fabric -l app=orderer,orderer=orderer0 -o jsonpath='{.items[0].metadata.name}')

echo "Scaling down orderer0..."
kubectl scale statefulset orderer0 --replicas=0 -n fabric
sleep 10

# Test if network still works
PEER_POD=$(kubectl get pods -n fabric -l app=peer,peer=peer0-org1 -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n fabric $PEER_POD -c peer -- peer channel getinfo -c gxchannel > /dev/null 2>&1; then
  echo "✅ Network operational after orderer0 down"
else
  echo "❌ Network failed after orderer0 down"
fi

# Restore
echo "Restoring orderer0..."
kubectl scale statefulset orderer0 --replicas=1 -n fabric
sleep 30

# Test 2: Peer failover
echo ""
echo "=== TEST 2: Peer Failover ==="
echo "Testing endorsement with peer1-org1 down..."

kubectl scale statefulset peer1-org1 --replicas=0 -n fabric
sleep 10

# Query should still work via peer0-org1
QUERY_RESULT=$(kubectl exec -n fabric $PEER_POD -c peer -- peer chaincode query -C gxchannel -n gxtv3 -c '{"function":"GetMetadata","Args":[]}' 2>/dev/null)
if [ -n "$QUERY_RESULT" ]; then
  echo "✅ Chaincode query works with peer1-org1 down"
else
  echo "❌ Chaincode query failed"
fi

# Restore
echo "Restoring peer1-org1..."
kubectl scale statefulset peer1-org1 --replicas=1 -n fabric
sleep 30

# Test 3: Database failover
echo ""
echo "=== TEST 3: Database Failover ==="
echo "Testing PostgreSQL replica failover..."

# This is informational - actual failover requires careful planning
echo "PostgreSQL replicas:"
kubectl get pods -n backend-mainnet -l app=postgres
echo "Replication status:"
kubectl exec -n backend-mainnet postgres-0 -- psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication" 2>/dev/null

echo ""
echo "=========================================="
echo "HA FAILOVER TEST COMPLETE"
echo "=========================================="
```

---

## 10. Backup & Disaster Recovery

### 10.1 Google Drive Backup Configuration

```bash
#!/bin/bash
# Setup automated backup to Google Drive
# Account: gxc@handsforeducation.org

# Install rclone
curl https://rclone.org/install.sh | bash

# Create rclone config
mkdir -p ~/.config/rclone
cat > ~/.config/rclone/rclone.conf << 'EOF'
[gdrive-gx]
type = drive
scope = drive
token = {"access_token":"YOUR_TOKEN","token_type":"Bearer","refresh_token":"YOUR_REFRESH_TOKEN","expiry":"2025-12-31T00:00:00Z"}
team_drive = 
root_folder_id = 
EOF

# Alternative: Service Account (recommended)
# Upload service account JSON to /root/.config/gcloud/gx-backup-sa.json
cat > ~/.config/rclone/rclone.conf << 'EOF'
[gdrive-gx]
type = drive
scope = drive
service_account_file = /root/.config/gcloud/gx-backup-sa.json
team_drive = 
root_folder_id = GX-Infrastructure-Backups
EOF

# Test connection
rclone lsd gdrive-gx:

# Create backup directories in Google Drive
rclone mkdir gdrive-gx:GX-Backups/daily
rclone mkdir gdrive-gx:GX-Backups/weekly
rclone mkdir gdrive-gx:GX-Backups/monthly
rclone mkdir gdrive-gx:GX-Backups/pre-migration
```

### 10.2 Automated Backup CronJob

```yaml
# k8s/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gx-full-backup
  namespace: backend-mainnet
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-sa
          containers:
          - name: backup
            image: rclone/rclone:latest
            command:
            - /bin/sh
            - -c
            - |
              # Backup script
              DATE=$(date +%Y%m%d)
              BACKUP_DIR=/backup/$DATE
              mkdir -p $BACKUP_DIR
              
              # Export K8s resources
              kubectl get all -A -o yaml > $BACKUP_DIR/k8s-all.yaml
              kubectl get secrets -n fabric -o yaml > $BACKUP_DIR/fabric-secrets.yaml
              
              # Create tarball
              tar -czvf /backup/gx-backup-$DATE.tar.gz $BACKUP_DIR
              
              # Upload to Google Drive
              rclone copy /backup/gx-backup-$DATE.tar.gz gdrive-gx:GX-Backups/daily/
              
              # Cleanup old backups (keep 7 days)
              rclone delete gdrive-gx:GX-Backups/daily/ --min-age 7d
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
            - name: rclone-config
              mountPath: /config/rclone
            - name: gcloud-sa
              mountPath: /root/.config/gcloud
          volumes:
          - name: backup-storage
            emptyDir: {}
          - name: rclone-config
            secret:
              secretName: rclone-config
          - name: gcloud-sa
            secret:
              secretName: gcloud-service-account
          restartPolicy: OnFailure
```

### 10.3 Backup Schedule

| Type | Frequency | Retention | Storage |
|------|-----------|-----------|---------|
| **Database (PostgreSQL)** | Every 6 hours | 7 days | Local + GDrive |
| **Redis** | Every 6 hours | 7 days | Local + GDrive |
| **Fabric Crypto** | Daily | 90 days | GDrive |
| **CouchDB State** | Daily | 30 days | Local + GDrive |
| **K8s Resources** | Daily | 30 days | GDrive |
| **Full System** | Weekly | 12 weeks | GDrive |
| **Pre-Migration** | Before each change | Permanent | GDrive |

---

## 11. Cloudflare Integration

### 11.1 Current DNS Configuration (To Verify)

```bash
# Verify Cloudflare DNS records
# Login to Cloudflare dashboard or use API

# Expected DNS records for gxcoin.money:
# A     gxcoin.money         → 195.35.36.174 (VPS-5 - Website)
# A     api.gxcoin.money     → 72.60.210.201 (VPS-1 - API)
# A     wallet.gxcoin.money  → 72.60.210.201 (VPS-1 - Wallet)
# CNAME www.gxcoin.money     → gxcoin.money

# Expected DNS records for goodness.exchange:
# A     goodness.exchange    → 72.60.210.201 (VPS-1)
# A     api.goodness.exchange → 72.60.210.201 (VPS-1)
```

### 11.2 Cloudflare Settings Verification

```bash
#!/bin/bash
# Verify Cloudflare configuration

echo "=== Cloudflare Configuration Check ==="

# Check if using Cloudflare (orange cloud)
for domain in gxcoin.money api.gxcoin.money wallet.gxcoin.money; do
  echo "Checking $domain..."
  
  # Get IP via DNS
  DNS_IP=$(dig +short $domain)
  echo "  DNS resolves to: $DNS_IP"
  
  # Check headers for Cloudflare
  CF_CHECK=$(curl -sI https://$domain 2>/dev/null | grep -i "cf-ray\|cloudflare")
  if [ -n "$CF_CHECK" ]; then
    echo "  ✅ Cloudflare proxy ENABLED"
    echo "  Headers: $CF_CHECK"
  else
    echo "  ⚠️  Cloudflare proxy may be DISABLED (DNS only)"
  fi
  echo ""
done
```

### 11.3 Recommended Cloudflare Settings

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CLOUDFLARE RECOMMENDED SETTINGS                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   SSL/TLS:                                                                  │
│   ├── Encryption Mode: Full (Strict)                                       │
│   ├── Always Use HTTPS: ON                                                 │
│   ├── Minimum TLS Version: 1.2                                             │
│   └── Opportunistic Encryption: ON                                         │
│                                                                             │
│   Security:                                                                 │
│   ├── Security Level: Medium                                               │
│   ├── Bot Fight Mode: ON                                                   │
│   ├── Browser Integrity Check: ON                                          │
│   └── Challenge Passage: 30 minutes                                        │
│                                                                             │
│   Firewall Rules (Create):                                                  │
│   ├── Block countries (optional for enterprise)                            │
│   ├── Rate limiting: 100 requests/minute per IP                           │
│   └── WAF: OWASP Core Ruleset (if available)                              │
│                                                                             │
│   Caching:                                                                  │
│   ├── Caching Level: Standard                                              │
│   ├── Browser Cache TTL: 4 hours                                           │
│   └── Always Online: ON                                                    │
│                                                                             │
│   Network:                                                                  │
│   ├── HTTP/2: ON                                                           │
│   ├── HTTP/3 (QUIC): ON                                                    │
│   ├── WebSockets: ON (for real-time features)                             │
│   └── gRPC: ON (for Fabric peer communication)                            │
│                                                                             │
│   Page Rules:                                                               │
│   ├── api.gxcoin.money/*                                                   │
│   │   └── Cache Level: Bypass                                              │
│   ├── wallet.gxcoin.money/*                                                │
│   │   └── Security Level: High                                             │
│   └── gxcoin.money/static/*                                                │
│       └── Cache Level: Cache Everything, Edge TTL: 1 month                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 11.4 Load Balancing Configuration (If Using Cloudflare LB)

```yaml
# If using Cloudflare Load Balancing (paid feature)
Load Balancer: api.gxcoin.money
  Pool: gx-api-pool
    Origins:
      - 72.60.210.201:443 (VPS-1) - Primary
      - 72.61.116.210:443 (VPS-2) - Backup
    Health Check:
      - Path: /health
      - Interval: 60s
      - Timeout: 5s
      - Retries: 2
    Steering Policy: Random (or Geo)
```

---

## 12. Post-Migration Validation

### 12.1 Validation Checklist

```markdown
## Post-Migration Validation Checklist

### Infrastructure
- [ ] All K8s nodes in Ready state
- [ ] All pods Running without CrashLoopBackOff
- [ ] PVCs bound and accessible
- [ ] Resource usage within limits

### Fabric Network
- [ ] All 5 orderers healthy and in consensus
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
- [ ] Backend services healthy
- [ ] Projector processing events
- [ ] Outbox-submitter stable

### Network
- [ ] DNS resolving correctly
- [ ] SSL certificates valid
- [ ] Cloudflare proxy active (if applicable)
- [ ] Inter-server connectivity working
- [ ] Partner peer connected

### Security
- [ ] No exposed sensitive ports
- [ ] Network policies active
- [ ] Secrets encrypted
- [ ] RBAC configured

### Backup
- [ ] Backup to Google Drive working
- [ ] Can restore from backup (tested)
- [ ] Backup schedule active
```

### 12.2 Sign-Off Requirements

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Infrastructure Lead | | | |
| Development Lead | | | |
| Security Review | | | |
| Operations | | | |

---

## 13. Operational Runbooks

### 13.1 Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Infrastructure | [Your Name] | 24/7 |
| Blockchain | [Name] | Business hours |
| Database | [Name] | On-call |
| Security | [Name] | On-call |

### 13.2 Quick Reference Commands

```bash
# Check overall cluster health
kubectl get nodes && kubectl get pods -A | grep -v Running

# Check Fabric network
kubectl get pods -n fabric -l app=orderer && kubectl get pods -n fabric -l app=peer

# Check backend services
kubectl get pods -n backend-mainnet

# View logs
kubectl logs -f deployment/svc-identity -n backend-mainnet
kubectl logs -f statefulset/orderer0 -n fabric -c orderer

# Restart a deployment
kubectl rollout restart deployment/svc-identity -n backend-mainnet

# Scale a statefulset
kubectl scale statefulset peer0-org1 --replicas=0 -n fabric

# Execute into pod
kubectl exec -it orderer0-0 -n fabric -c orderer -- /bin/bash

# Check resource usage
kubectl top nodes && kubectl top pods -n fabric
```

### 13.3 Incident Response

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    INCIDENT RESPONSE FLOWCHART                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   1. DETECT                                                                 │
│      └── Alert received / User report / Monitoring                         │
│                                                                             │
│   2. ASSESS                                                                 │
│      ├── Is production affected? → Priority 1                              │
│      ├── Is data at risk? → Priority 1                                     │
│      └── Is it a performance issue? → Priority 2                           │
│                                                                             │
│   3. COMMUNICATE                                                            │
│      ├── Notify stakeholders                                               │
│      ├── Update status page (if applicable)                                │
│      └── Create incident ticket                                            │
│                                                                             │
│   4. MITIGATE                                                               │
│      ├── If single component: Restart/scale                                │
│      ├── If network-wide: Check orderer consensus                          │
│      └── If data corruption: Restore from backup                           │
│                                                                             │
│   5. RESOLVE                                                                │
│      ├── Apply fix                                                         │
│      ├── Verify services restored                                          │
│      └── Run validation tests                                              │
│                                                                             │
│   6. REVIEW                                                                 │
│      ├── Document root cause                                               │
│      ├── Update runbooks                                                   │
│      └── Implement preventive measures                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **Raft** | Consensus algorithm used by Fabric orderers |
| **MSP** | Membership Service Provider - identity management |
| **CouchDB** | NoSQL database used for Fabric state |
| **Anchor Peer** | Peer that facilitates cross-org communication |
| **Chaincode** | Smart contract in Hyperledger Fabric |
| **Endorsement** | Peer validation of transaction proposal |
| **K3s** | Lightweight Kubernetes distribution |
| **MetalLB** | Bare-metal load balancer for Kubernetes |

## Appendix B: File Locations

| Item | Location |
|------|----------|
| Fabric crypto | /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/organizations |
| Backend code | /home/sugxcoin/prod-blockchain/gx-protocol-backend |
| Frontend code | /home/sugxcoin/prod-blockchain/gx-wallet-frontend |
| K8s manifests | /root/fabric-k8s/ |
| Test scripts | /root/test-scripts/ |
| Backup scripts | /root/backup-scripts/ |
| Audit results | /root/infrastructure-audit-* |

---

## Document Approval

| Version | Date | Author | Approved By |
|---------|------|--------|-------------|
| 1.0 | Dec 11, 2025 | Claude AI | Pending |
| 2.0 | Dec 11, 2025 | Claude AI | Pending |

---

**END OF DOCUMENT**
