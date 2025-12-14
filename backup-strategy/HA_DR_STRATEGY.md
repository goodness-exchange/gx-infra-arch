# GX Coin Protocol - High Availability & Disaster Recovery Strategy

**Version:** 1.0
**Date:** December 14, 2025
**Status:** PROPOSED - Pending Implementation

---

## Executive Summary

This document defines the comprehensive High Availability (HA) and Disaster Recovery (DR) strategy for the GX Coin Protocol infrastructure. The strategy addresses the critical gaps identified in the backup audit and provides a roadmap for achieving production-grade resilience.

**Key Principle:** HA is about service availability, not just having backups. The focus is on **Recovery Time Objective (RTO)** - how quickly we can restore service.

---

## Current State Assessment

### Critical Issues Identified

| Issue | Severity | Impact |
|-------|----------|--------|
| PostgreSQL NOT replicated | CRITICAL | Complete data loss if node fails |
| Backup scripts failing (kubectl PATH) | CRITICAL | No valid backups since Dec 12 |
| K8s CronJob backups empty | CRITICAL | 20-byte empty files |
| CouchDB not backed up | HIGH | Fabric state data at risk |
| Container images not backed up | HIGH | Cannot redeploy services |
| Redis backups failing | MEDIUM | Session data loss |
| No cross-region backup replication | MEDIUM | Single point of failure |

### Current Single Points of Failure

```
                    ┌─────────────────────────────────────────────┐
                    │         SINGLE POINTS OF FAILURE            │
                    ├─────────────────────────────────────────────┤
                    │                                             │
  ┌─────────────────┴───────────────────────────────────────────┐ │
  │  srv1089618.hstgr.cloud (VPS-1) - Kuala Lumpur              │ │
  │  ┌─────────────────────────────────────────────────────────┐│ │
  │  │ postgres-0  ← ALL PRODUCTION DATA (38 tables)          ││ │
  │  │ redis-2                                                 ││ │
  │  │ couchdb-peer1-org1-0                                    ││ │
  │  │ orderer0-0, orderer3-0                                  ││ │
  │  │ peer0-org1-0                                            ││ │
  │  └─────────────────────────────────────────────────────────┘│ │
  │  IF THIS NODE FAILS: COMPLETE DATA LOSS                     │ │
  └─────────────────────────────────────────────────────────────┘ │
                    │                                             │
  ┌─────────────────┴───────────────────────────────────────────┐ │
  │  srv1089624.hstgr.cloud (VPS-2) - Phoenix, USA              │ │
  │  ┌─────────────────────────────────────────────────────────┐│ │
  │  │ redis-0, postgres-2 (empty)                             ││ │
  │  │ couchdb-peer0-org1-0, couchdb-peer1-org2-0              ││ │
  │  │ orderer1-0                                              ││ │
  │  └─────────────────────────────────────────────────────────┘│ │
  └─────────────────────────────────────────────────────────────┘ │
                    │                                             │
  ┌─────────────────┴───────────────────────────────────────────┐ │
  │  srv1092158.hstgr.cloud (VPS-3) - Frankfurt, Germany        │ │
  │  ┌─────────────────────────────────────────────────────────┐│ │
  │  │ postgres-1 (empty), redis-1                             ││ │
  │  │ couchdb-peer0-org2-0                                    ││ │
  │  │ orderer2-0                                              ││ │
  │  └─────────────────────────────────────────────────────────┘│ │
  └─────────────────────────────────────────────────────────────┘ │
                    └─────────────────────────────────────────────┘
```

---

## Target State Architecture

### Recovery Objectives

| Scenario | Current RTO | Target RTO | Current RPO | Target RPO |
|----------|-------------|------------|-------------|------------|
| Single Pod Failure | Minutes | Minutes | 0 | 0 |
| Single Node Failure | INFINITE | < 30 min | INFINITE | < 6 hours |
| Regional Failure | INFINITE | < 4 hours | INFINITE | < 6 hours |
| Complete Cluster Loss | INFINITE | < 24 hours | INFINITE | < 24 hours |

**RTO** = Recovery Time Objective (how long to restore service)
**RPO** = Recovery Point Objective (how much data can be lost)

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        TARGET HA ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────┐    ┌──────────────────────┐                       │
│  │   Primary Region     │    │   Secondary Region   │                       │
│  │   (Multi-AZ)         │    │   (DR Site)          │                       │
│  │                      │    │                      │                       │
│  │  ┌────────────────┐  │    │  ┌────────────────┐  │                       │
│  │  │ PostgreSQL     │──┼────┼─▶│ PostgreSQL     │  │  Streaming            │
│  │  │ Primary        │  │    │  │ Standby        │  │  Replication          │
│  │  └────────────────┘  │    │  └────────────────┘  │                       │
│  │                      │    │                      │                       │
│  │  ┌────────────────┐  │    │  ┌────────────────┐  │                       │
│  │  │ Redis Cluster  │──┼────┼─▶│ Redis Replica  │  │  Async                │
│  │  │ (Sentinel)     │  │    │  │                │  │  Replication          │
│  │  └────────────────┘  │    │  └────────────────┘  │                       │
│  │                      │    │                      │                       │
│  │  ┌────────────────┐  │    │  ┌────────────────┐  │                       │
│  │  │ Fabric Network │  │    │  │ Fabric Network │  │  Ledger               │
│  │  │ (5 Orderers,   │──┼────┼─▶│ (Orderer      │  │  Replication          │
│  │  │  4 Peers)      │  │    │  │  Snapshot)     │  │  (Built-in)           │
│  │  └────────────────┘  │    │  └────────────────┘  │                       │
│  └──────────────────────┘    └──────────────────────┘                       │
│              │                          │                                    │
│              └───────────┬──────────────┘                                    │
│                          │                                                   │
│                          ▼                                                   │
│               ┌────────────────────┐                                        │
│               │   Google Drive     │  Off-site Backup                       │
│               │   (Encrypted)      │  (30-day retention)                    │
│               └────────────────────┘                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Backup Strategy

### Backup Matrix

| Component | Method | Frequency | Retention | Location | Priority |
|-----------|--------|-----------|-----------|----------|----------|
| PostgreSQL | pg_dump + streaming replication | 6 hours + real-time | 30 days | Local PVC + GDrive | P1 |
| Redis | RDB snapshot | 6 hours | 7 days | Local PVC + GDrive | P2 |
| CouchDB | tar archive | 6 hours | 30 days | GDrive | P1 |
| Fabric CA | tar archive | Daily | 90 days | GDrive | P1 |
| Fabric Secrets | kubectl export | Daily | 90 days | GDrive | P1 |
| etcd | K3s automatic | 12 hours | 5 snapshots | Local + GDrive | P1 |
| K8s Manifests | kubectl export | Daily | 90 days | GDrive | P2 |
| Container Images | Registry mirror | On push | Indefinite | Docker Hub | P2 |

### Backup Schedule

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           BACKUP SCHEDULE (UTC)                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  00:00  ┌──────────────────────────────────────────────────────┐             │
│         │ etcd snapshot (K3s automatic)                        │             │
│         └──────────────────────────────────────────────────────┘             │
│                                                                               │
│  04:00  ┌──────────────────────────────────────────────────────┐             │
│         │ Full MainNet Backup:                                  │             │
│         │ - PostgreSQL pg_dumpall                               │             │
│         │ - Redis BGSAVE + copy                                 │             │
│         │ - CouchDB tar (all 4 instances)                       │             │
│         │ - Fabric CA crypto (all 5 CAs)                        │             │
│         │ - K8s secrets, configmaps, PVCs                       │             │
│         │ - etcd latest snapshot                                │             │
│         │ → Upload to Google Drive                              │             │
│         └──────────────────────────────────────────────────────┘             │
│                                                                               │
│  06:00  ┌──────────────────────────────────────────────────────┐             │
│  12:00  │ Incremental Backup:                                   │             │
│  18:00  │ - PostgreSQL pg_dump                                  │             │
│         │ - Redis snapshot                                      │             │
│         │ → Upload to Google Drive                              │             │
│         └──────────────────────────────────────────────────────┘             │
│                                                                               │
│  12:00  ┌──────────────────────────────────────────────────────┐             │
│         │ etcd snapshot (K3s automatic)                        │             │
│         └──────────────────────────────────────────────────────┘             │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Disaster Recovery Procedures

### Scenario 1: Single Pod Failure

**RTO: Minutes | RPO: 0**

```bash
# Kubernetes will automatically reschedule the pod
# No action required unless pod stays in CrashLoopBackOff

# Check pod status
kubectl get pods -n <namespace> -o wide

# If stuck, delete and let K8s recreate
kubectl delete pod <pod-name> -n <namespace>
```

### Scenario 2: Single Node Failure (e.g., srv1089618 fails)

**RTO: < 30 min | RPO: < 6 hours (with proper backups)**

**Impact:** postgres-0 (ALL DATA), redis-2, couchdb-peer1-org1-0, orderer0-0, orderer3-0, peer0-org1-0

**Recovery Steps:**

```bash
# 1. Verify node is actually down
kubectl get nodes
kubectl describe node srv1089618.hstgr.cloud

# 2. If node is dead, remove it from cluster
kubectl drain srv1089618.hstgr.cloud --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node srv1089618.hstgr.cloud

# 3. PostgreSQL Recovery (CRITICAL)
# Download latest backup from Google Drive
rclone copy gdrive-gx:GX-Infrastructure-Backups/mainnet/latest/ /tmp/restore/

# Restore to a surviving PostgreSQL pod
kubectl exec -n backend-mainnet postgres-1 -- psql -U gx_admin -f /tmp/restore/postgres-mainnet.sql

# Update service to point to new primary
kubectl patch svc postgres-primary -n backend-mainnet -p '{"spec":{"selector":{"statefulset.kubernetes.io/pod-name":"postgres-1"}}}'

# 4. Redis Recovery
# Redis data will be lost, but it's mostly cache/session data
# Restart services to reconnect to surviving Redis

# 5. Fabric Recovery
# Fabric has built-in fault tolerance:
# - Orderers: Need 3/5 for consensus (losing 2 is OK)
# - Peers: Can resync from other peers
# Wait for Kubernetes to reschedule pods on other nodes

# 6. Verify services
kubectl get pods -A -o wide
```

### Scenario 3: Complete Data Loss

**RTO: < 24 hours | RPO: < 24 hours**

**Recovery Steps:**

```bash
# 1. Provision new infrastructure (K3s cluster)
# Use Terraform/Ansible scripts in gx-infra-arch/

# 2. Install K3s on new nodes
curl -sfL https://get.k3s.io | sh -s - server --cluster-init

# 3. Restore etcd from snapshot
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/path/to/etcd-snapshot

# 4. Apply K8s manifests
kubectl apply -f /restore/k8s-state/all-resources.yaml

# 5. Restore databases
# PostgreSQL
kubectl cp /restore/postgres-mainnet.sql backend-mainnet/postgres-0:/tmp/
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -f /tmp/postgres-mainnet.sql

# 6. Restore Fabric CA crypto
for ca in ca-root-0 ca-org1-0 ca-org2-0 ca-orderer-0 ca-tls-0; do
    kubectl cp /restore/fabric-crypto/${ca}.tar.gz fabric/${ca}:/tmp/
    kubectl exec -n fabric ${ca} -- tar -xzf /tmp/${ca}.tar.gz -C /
done

# 7. Restore CouchDB
for couch in couchdb-peer0-org1-0 couchdb-peer0-org2-0; do
    kubectl cp /restore/couchdb/${couch}.tar.gz fabric/${couch}:/tmp/
    kubectl exec -n fabric ${couch} -- tar -xzf /tmp/${couch}.tar.gz -C /
done

# 8. Restart all services
kubectl rollout restart deployment -n backend-mainnet
kubectl rollout restart statefulset -n fabric

# 9. Verify Fabric network
kubectl exec -n fabric peer0-org1-0 -- peer channel list
kubectl exec -n fabric peer0-org1-0 -- peer chaincode list --installed
```

---

## High Availability Implementation

### Phase 1: Immediate (Week 1)

**Goal:** Fix backup system to enable basic DR

| Task | Description | Status |
|------|-------------|--------|
| Fix kubectl PATH | Add full path to all backup scripts | TODO |
| Fix PostgreSQL backup | Use correct service endpoint | TODO |
| Add CouchDB backup | Include in backup rotation | TODO |
| Fix Redis authentication | Get password from secret | TODO |
| Verify backups | Test restoration procedure | TODO |

### Phase 2: Short-term (Week 2-4)

**Goal:** Implement PostgreSQL replication

| Task | Description | Status |
|------|-------------|--------|
| PostgreSQL streaming replication | Configure primary-standby | TODO |
| Automatic failover | Use Patroni or pgpool-II | TODO |
| Cross-node PVC distribution | Ensure data on multiple nodes | TODO |
| Backup verification automation | Daily restore tests | TODO |

### Phase 3: Medium-term (Month 2-3)

**Goal:** Full HA with multi-region DR

| Task | Description | Status |
|------|-------------|--------|
| Container image registry | Push to Docker Hub + GCR | TODO |
| Cross-region backup sync | Replicate to VPS-4 | TODO |
| Monitoring & alerting | Prometheus alerts for backup failures | TODO |
| DR runbook automation | Ansible playbooks for recovery | TODO |

---

## Monitoring & Alerting

### Backup Health Checks

```yaml
# Prometheus Alerting Rules
groups:
  - name: backup-alerts
    rules:
      - alert: BackupOlderThan24Hours
        expr: time() - backup_last_success_timestamp > 86400
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "No successful backup in 24 hours"

      - alert: BackupSizeTooSmall
        expr: backup_size_bytes < 50000
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Backup file suspiciously small"

      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag_seconds > 60
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL replication lag exceeds 60 seconds"
```

### Health Check Script

```bash
#!/bin/bash
# /root/scripts/check-backup-health.sh

REMOTE="gdrive-gx:GX-Infrastructure-Backups/mainnet"

# Check latest backup age
LATEST=$(rclone lsd ${REMOTE}/ | tail -1 | awk '{print $5}')
AGE_DAYS=$(( ($(date +%s) - $(date -d "${LATEST}" +%s)) / 86400 ))

if [ $AGE_DAYS -gt 1 ]; then
    echo "CRITICAL: Last backup is ${AGE_DAYS} days old"
    exit 2
elif [ $AGE_DAYS -eq 1 ]; then
    echo "WARNING: Last backup is 1 day old"
    exit 1
else
    echo "OK: Last backup: ${LATEST}"
    exit 0
fi
```

---

## Container Image Strategy

### Current Images to Preserve

```
CRITICAL (Custom):
- 10.43.75.195:5000/gxtv3-chaincode:1.211
- docker.io/gx-protocol/outbox-submitter:2.1.0
- docker.io/gx-protocol/projector:2.1.0
- docker.io/gx-protocol/svc-admin:2.1.0
- docker.io/gx-protocol/svc-identity:2.1.0
- docker.io/gx-protocol/svc-governance:2.1.0
- docker.io/gx-protocol/svc-organization:2.1.0
- docker.io/gx-protocol/svc-loanpool:2.1.0
- docker.io/gx-protocol/svc-tax:2.1.0
- docker.io/gx-protocol/svc-tokenomics:2.1.0

STANDARD (Pull from Docker Hub):
- hyperledger/fabric-peer:2.5
- hyperledger/fabric-orderer:2.5
- couchdb:3.3
- postgres:15-alpine
- redis:7-alpine
```

### Recommendation

1. **Push all custom images to Docker Hub** with organization `gx-protocol`
2. **Tag with version and `latest`** for easy recovery
3. **Store Dockerfiles** in Git for rebuild capability

---

## Files Created

| File | Purpose |
|------|---------|
| `/root/scripts/backup-mainnet-fixed.sh` | Fixed comprehensive backup script |
| `/root/emergency-backups/` | Emergency backup directory (uploaded to GDrive) |
| `BACKUP_AUDIT_20251214.md` | Detailed audit findings |
| `HA_DR_STRATEGY.md` | This document |

---

## Recommended Immediate Actions

### Priority 1: Today

1. **Verify emergency backup on Google Drive**
   ```bash
   rclone ls gdrive-gx:GX-Infrastructure-Backups/mainnet/emergency/
   ```

2. **Schedule manual backup until automated backup is fixed**
   - Run `/root/scripts/backup-mainnet-fixed.sh` manually daily

### Priority 2: This Week

3. **Apply fixes to backup scripts**
   - Add `export PATH=/usr/local/bin:$PATH` to all cron scripts
   - Update PostgreSQL backup to use correct endpoint
   - Add CouchDB to backup rotation

4. **Test restoration procedure**
   - Download backup from Google Drive
   - Restore to testnet environment
   - Verify data integrity

### Priority 3: This Month

5. **Implement PostgreSQL streaming replication**
6. **Set up monitoring alerts for backup failures**
7. **Create automated DR runbooks**

---

## Conclusion

The current backup infrastructure has critical gaps that leave the GX Coin Protocol vulnerable to complete data loss. The emergency backup taken today (13.2 MB) provides a recovery point, but systematic fixes are required to achieve production-grade resilience.

**Key Metrics:**
- Emergency backup uploaded: `gdrive-gx:GX-Infrastructure-Backups/mainnet/emergency/emergency-backup-20251214.tar.gz`
- Backup size: 13.2 MB
- Contains: PostgreSQL dump, CouchDB snapshots, K8s state, etcd snapshot, Fabric secrets

**Next Steps:**
1. Review this strategy document
2. Approve implementation plan
3. Execute Priority 1 actions immediately
4. Schedule Priority 2 and 3 work

---

*Document Generated: December 14, 2025*
