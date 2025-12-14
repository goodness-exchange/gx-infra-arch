# Backup Strategy Audit Report

**Date:** December 14, 2025
**Auditor:** Infrastructure Team
**Status:** CRITICAL ISSUES FOUND

---

## Executive Summary

A comprehensive audit of the backup infrastructure revealed **multiple critical failures** that leave the GX Coin Protocol vulnerable to complete data loss. **No valid backups currently exist** for most critical data, and the PostgreSQL "cluster" is not actually replicated.

### Severity: CRITICAL

**Immediate Risk:** Complete data loss possible if any primary node fails.

---

## Critical Findings

### 1. Cron-Based Backups FAILING (kubectl not in PATH)

**Issue:** All cron-based backup scripts fail because `kubectl` is not in the cron PATH environment.

**Evidence:**
```
/root/backup-scripts/gx-full-backup.sh: line 82: kubectl: command not found
/root/scripts/backup-mainnet.sh: line 37: kubectl: command not found
```

**Impact:**
- `/root/backups/daily/` - EMPTY
- `/root/backups/weekly/` - EMPTY
- `/root/backups/monthly/` - EMPTY
- Google Drive mainnet backups failing since Dec 13

**Affected Scripts:**
- `/root/backup-scripts/gx-full-backup.sh` (daily 2AM, weekly 3AM, monthly 4AM)
- `/root/scripts/backup-mainnet.sh` (daily 4AM)

---

### 2. Kubernetes PostgreSQL CronJob Creating EMPTY Backups

**Issue:** The PostgreSQL backup CronJob connects to `postgres-primary` service which is misconfigured, resulting in connection refused errors. The script creates 20-byte empty gzip files.

**Evidence:**
```
pg_dump: error: connection to server at "postgres-primary" (10.43.185.5), port 5432 failed: Connection refused
Backup size: 4.0K  (should be ~180KB minimum)
```

**All backup files are 20 bytes (empty):**
```
-rw-rw-r-- 1 999 ping 20 Dec 14 06:00 gx-protocol-20251214-060007.sql.gz
```

**Impact:** No valid PostgreSQL backups for the past 7+ days.

---

### 3. PostgreSQL "Cluster" is NOT Replicated

**Issue:** The 3 PostgreSQL StatefulSet replicas are independent databases, NOT a replicated cluster.

**Evidence:**
```sql
-- postgres-0 (primary): 38 tables with data
-- postgres-1 (replica): 0 tables (EMPTY!)
-- postgres-2 (replica): 0 tables (EMPTY!)
-- pg_stat_replication: 0 rows
```

**Impact:**
- All production data exists ONLY on postgres-0
- If the node hosting postgres-0 (srv1089618.hstgr.cloud) fails, ALL DATA IS LOST
- The "3 replicas" provide ZERO redundancy

---

### 4. Redis Backup CronJob FAILING

**Issue:** The Redis backup script uses `kubectl cp` but kubectl is not available in the backup pod container.

**Evidence:**
```
/scripts/backup.sh: line 27: kubectl: not found
RDB copy failed
No backups found
```

**Impact:** No valid Redis backups exist.

---

### 5. CouchDB (Fabric State Database) NOT Backed Up

**Issue:** CouchDB contains the Hyperledger Fabric world state but has no backup mechanism at all.

**Data at Risk:**
- 4 CouchDB instances (peer0-org1, peer0-org2, peer1-org1, peer1-org2)
- ~3.5MB per instance = ~14MB total of blockchain state

**Impact:** If CouchDB data is lost, Fabric peers cannot function properly.

---

### 6. Orderer/Peer Ledger Data NOT Backed Up

**Issue:** Blockchain ledger data stored in orderer and peer PVCs has no backup mechanism.

**Data at Risk:**
- 5 Orderer ledgers (10Gi each)
- 4 Peer ledgers (10Gi each)

---

### 7. Container Images NOT Backed Up

**Issue:** 35GB of container images with no backup strategy.

**Critical Images:**
- gx-protocol/* service images (svc-admin, svc-identity, projector, etc.)
- gxtv3-chaincode (custom chaincode)
- Hyperledger Fabric images

**Impact:** If private registry fails, services cannot be redeployed.

---

### 8. Pre-Migration Backup is INCOMPLETE

**Issue:** The pre-migration backup from Dec 13 contains minimal data.

**Evidence:**
- PostgreSQL dump: 182KB (should be much larger with real data)
- Redis dump: 88 bytes (essentially empty)
- Total archive: 340KB (far too small)

---

### 9. Deprecated Incremental Backup Script Still in Crontab

**Issue:** Crontab references a moved/deleted script.

```
0 */4 * * * /home/sugxcoin/prod-blockchain/gx-coin-fabric/scripts/phase0-backup-incremental-CORRECTED.sh
```

The script was moved to `_deprecated/` but cron still tries to run it.

---

## Current Backup Status Summary

| Component | Backup Method | Status | Last Valid Backup |
|-----------|--------------|--------|-------------------|
| PostgreSQL (MainNet) | K8s CronJob | FAILING | NEVER |
| PostgreSQL (MainNet) | Cron script | FAILING | Dec 12 (partial) |
| Redis | K8s CronJob | FAILING | NEVER |
| CouchDB (4 instances) | NONE | NO BACKUP | NEVER |
| Orderer Ledgers (5) | NONE | NO BACKUP | NEVER |
| Peer Ledgers (4) | NONE | NO BACKUP | NEVER |
| Fabric CA Data (5) | Cron script | FAILING | Dec 13 (partial) |
| Container Images | NONE | NO BACKUP | NEVER |
| etcd Snapshots | K3s automatic | WORKING | Dec 14 00:00 |
| K8s Secrets/ConfigMaps | Cron script | FAILING | Dec 13 (partial) |

---

## Single Points of Failure Analysis

### If srv1089618.hstgr.cloud (VPS-1) Fails:

**LOST DATA:**
- postgres-0 (ALL production data - CRITICAL)
- redis-2
- couchdb-peer1-org1-0
- orderer0-0, orderer3-0
- peer0-org1-0

**Recovery:** IMPOSSIBLE without backups

### If srv1089624.hstgr.cloud (VPS-2) Fails:

**LOST DATA:**
- couchdb-peer0-org1-0
- couchdb-peer1-org2-0
- orderer1-0
- redis-0

**Recovery:** Partial - Fabric can recover from other peers/orderers

### If srv1092158.hstgr.cloud (VPS-3) Fails:

**LOST DATA:**
- couchdb-peer0-org2-0
- orderer2-0

**Recovery:** Partial - Fabric can recover from other peers/orderers

---

## Recovery Time Objective (RTO) Assessment

| Scenario | Current RTO | Target RTO |
|----------|-------------|------------|
| Single Pod Failure | Minutes | Minutes |
| Single Node Failure | INFINITE (no backup) | < 4 hours |
| Regional Failure | INFINITE | < 8 hours |
| Complete Cluster Loss | INFINITE | < 24 hours |

---

## Recommended Immediate Actions

### Priority 1: Emergency (Do Today)

1. **Take manual backup NOW**
   ```bash
   kubectl exec -n backend-mainnet postgres-0 -- pg_dumpall -U gx_admin > /root/emergency-backup-$(date +%Y%m%d).sql
   ```

2. **Fix kubectl PATH in backup scripts**
   - Add `export PATH=/usr/local/bin:$PATH` at top of all scripts
   - Or use full path: `/usr/local/bin/kubectl`

3. **Fix PostgreSQL backup connection**
   - Change from `postgres-primary` to `postgres-0.postgres-headless`

### Priority 2: Critical (This Week)

4. **Implement PostgreSQL streaming replication**
   - Configure postgres-0 as primary
   - Configure postgres-1, postgres-2 as standby replicas

5. **Add CouchDB backup CronJob**

6. **Fix Redis backup script**
   - Use sidecar container or initContainer with kubectl

### Priority 3: Important (This Month)

7. **Container image backup strategy**
   - Push all images to Docker Hub or private registry with replication

8. **Cross-region backup replication**
   - Sync backups to multiple VPS nodes

9. **Implement backup verification**
   - Automated restore tests
   - Alerting on backup failures

---

## Google Drive Backup Inventory

| Path | Size | Date | Status |
|------|------|------|--------|
| mainnet/backup-mainnet-20251213_173825.tar.gz | 12.5 MB | Dec 13 | Partial (DB failed) |
| pre-migration/gx-full-backup-20251212-093047.tar.gz | 26.1 MB | Dec 12 | Partial |
| testnet/backup-testnet-20251214_030001.tar.gz | 2 KB | Dec 14 | Likely empty |
| website/backup-website-20251214_020002.tar.gz | 403 MB | Dec 14 | OK |

---

## Next Steps

1. Review and approve this audit report
2. Execute Priority 1 actions immediately
3. Schedule Priority 2 implementation
4. Update BACKUP_STRATEGY.md with fixes
5. Implement monitoring and alerting

---

*Report Generated: December 14, 2025*
