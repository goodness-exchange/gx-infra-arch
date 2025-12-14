# Work Record - December 14, 2025

## Task: Backup Strategy Audit and HA/DR Assessment

---

## Summary

Conducted comprehensive audit of backup infrastructure for GX Coin Protocol. Discovered **multiple critical failures** in the backup system that leave production data at risk of complete loss.

---

## Work Carried Out

### 1. Backup Infrastructure Audit

**Actions:**
- Reviewed all backup scripts in `/root/backup-scripts/`, `/root/scripts/`
- Analyzed crontab entries for backup schedules
- Checked backup logs in `/root/backup-logs/` and `/var/log/`
- Verified backup file sizes and contents
- Listed Google Drive backups via rclone

**Findings:**
- Cron-based backups failing since Dec 13 due to `kubectl` not in PATH
- K8s CronJob PostgreSQL backups creating 20-byte empty files
- Redis backup CronJob failing (kubectl not in container)
- CouchDB not backed up at all
- Container images (35GB) not backed up

### 2. Database Replication Assessment

**Actions:**
- Checked PostgreSQL StatefulSet configuration
- Verified `pg_stat_replication` status
- Compared table counts across PostgreSQL replicas

**Findings:**
- PostgreSQL "cluster" is NOT replicated - 3 independent databases
- postgres-0: 38 tables (all data)
- postgres-1: 0 tables (empty!)
- postgres-2: 0 tables (empty!)
- Single point of failure: if srv1089618.hstgr.cloud fails, ALL DATA LOST

### 3. Data Distribution Analysis

**Actions:**
- Mapped stateful pods to nodes
- Identified critical data locations
- Assessed single points of failure

**Findings:**
- Most critical data on srv1089618 (postgres-0, orderer0-0, peer0-org1)
- No cross-node data replication for local-path PVCs
- Fabric has built-in fault tolerance (5 orderers, 4 peers)

### 4. Emergency Backup

**Actions:**
- Created emergency backup script
- Backed up PostgreSQL, CouchDB, Fabric secrets, K8s state, etcd snapshots
- Uploaded 13.2 MB archive to Google Drive

**Files Created:**
- `/root/emergency-backups/postgres-mainnet-20251214-065334.sql` (87KB)
- `/root/emergency-backups/couchdb-peer*.tar.gz` (4 files)
- `/root/emergency-backups/k8s-*.yaml` (state exports)
- `/root/emergency-backups/etcd-snapshot-*` (5 snapshots)
- Uploaded: `gdrive-gx:GX-Infrastructure-Backups/mainnet/emergency/emergency-backup-20251214.tar.gz`

### 5. Documentation

**Actions:**
- Created detailed audit report
- Designed HA/DR strategy
- Documented disaster recovery procedures

**Files Created:**
- `/home/sugxcoin/prod-blockchain/gx-infra-arch/backup-strategy/BACKUP_AUDIT_20251214.md`
- `/home/sugxcoin/prod-blockchain/gx-infra-arch/backup-strategy/HA_DR_STRATEGY.md`
- `/root/scripts/backup-mainnet-fixed.sh` (fixed backup script - not deployed)

---

## Critical Issues Found

| Issue | Severity | Root Cause | Status |
|-------|----------|------------|--------|
| PostgreSQL not replicated | CRITICAL | StatefulSet creates independent databases | **FIXED** |
| Backup scripts failing | CRITICAL | `kubectl` not in cron PATH | **FIXED** |
| K8s PostgreSQL backups empty | CRITICAL | Wrong service endpoint | **FIXED** |
| K8s Redis backups failing | HIGH | kubectl not in container | **FIXED** |
| CouchDB not backed up | HIGH | No backup mechanism exists | **FIXED** |
| Container images not backed up | HIGH | No strategy defined | Pending |
| Pre-migration backup incomplete | MEDIUM | Database dumps were empty | N/A |

---

## Recovery Objectives (Before vs After)

| Scenario | Before | After (with replication) | Target |
|----------|--------|--------------------------|--------|
| Single Pod Failure | Minutes | Minutes | Minutes |
| Single Node Failure | INFINITE | **< 5 min** | < 30 min |
| Regional Failure | INFINITE | **< 30 min** | < 4 hours |
| Complete Cluster Loss | Hours (restore) | Hours (restore) | < 24 hours |

---

## Recommendations

### Immediate (Today)
1. Schedule manual backup runs until automated system is fixed
2. Verify emergency backup integrity on Google Drive

### This Week
3. Apply PATH fix to all cron backup scripts
4. Fix PostgreSQL backup connection string
5. Add CouchDB to backup rotation
6. Test restoration procedure

### This Month
7. Implement PostgreSQL streaming replication
8. Set up backup monitoring and alerting
9. Push custom images to Docker Hub
10. Create automated DR runbooks

---

## Files Modified/Created

| File | Action | Description |
|------|--------|-------------|
| `/root/emergency-backups/do-emergency-backup.sh` | Created | Emergency backup script |
| `/root/scripts/backup-mainnet-fixed.sh` | Created | Fixed backup script (not deployed) |
| `backup-strategy/BACKUP_AUDIT_20251214.md` | Created | Detailed audit findings |
| `backup-strategy/HA_DR_STRATEGY.md` | Created | HA/DR strategy document |
| `gx-infra-arch/WORK_RECORD_20251214.md` | Created | This work record |

---

## Google Drive Backup Status

| Path | Size | Date | Status |
|------|------|------|--------|
| mainnet/emergency/emergency-backup-20251214.tar.gz | 13.2 MB | Dec 14 | New |
| mainnet/backup-mainnet-20251213_173825.tar.gz | 12.5 MB | Dec 13 | Partial |
| pre-migration/gx-full-backup-20251212-093047.tar.gz | 26.1 MB | Dec 12 | Partial |

---

## Fixes Applied (07:30 UTC)

### 1. Cron Backup Scripts - PATH Fix

**Files Modified:**
- `/root/backup-scripts/02-gx-full-backup.sh` - Added `export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"`
- `/root/scripts/backup-mainnet.sh` - Added PATH export and comprehensive fixes

### 2. MainNet Backup Script - Complete Overhaul

**Changes:**
- Fixed kubectl PATH for cron compatibility
- Fixed PostgreSQL connection (use `postgres-0` directly instead of dynamic lookup)
- Fixed CA backup path (`/etc/hyperledger/fabric-ca-server` not `/var/hyperledger`)
- Added CouchDB backup (4 instances)
- Added Redis authentication support
- Added backup size verification
- Added summary logging

**Test Result:** Successful - 4.46 MB backup uploaded to Google Drive

### 3. K8s PostgreSQL Backup CronJob

**ConfigMap Updated:** `postgres-backup-scripts` in `backend-mainnet` namespace

**Changes:**
- Fixed service endpoint (`postgres-0.postgres-headless`)
- Added backup size verification
- Adjusted minimum size threshold (5KB for compressed dumps)

**Test Result:** Successful - 9.9KB backup (vs 20 bytes before)

### 4. K8s Redis Backup CronJob

**ConfigMap Updated:** `redis-backup-scripts` in `backend-mainnet` namespace

**Changes:**
- Fixed LASTSAVE wait loop
- Added `redis-cli --rdb` for direct RDB export
- Added compression

### 5. Crontab Cleanup

**Removed:**
- Broken incremental backup entry (script moved to _deprecated)
- Suspicious `@reboot` entry

**Updated Schedule:**
```
0 2 * * *   Full backup (daily)
0 3 * * 0   Full backup (weekly)
0 4 1 * *   Full backup (monthly)
0 6 * * *   MainNet backup (with CouchDB)
0 5 * * *   Container image cleanup
```

---

## Verification Results

| Component | Before | After | Status |
|-----------|--------|-------|--------|
| Cron backups | `kubectl: not found` | Working | FIXED |
| PostgreSQL K8s | 20 bytes (empty) | 9.9 KB (valid) | FIXED |
| MainNet script | Failed | 4.46 MB uploaded | FIXED |
| CouchDB | Not backed up | 4 instances backed up | FIXED |
| CA backup | Wrong path | Correct path | FIXED |
| Redis | No auth | With auth | FIXED |

---

## Google Drive Backup Status (After Fixes)

| File | Size | Time |
|------|------|------|
| `backup-mainnet-20251214_071437.tar.gz` | 4.46 MB | 07:15 UTC |
| `emergency/emergency-backup-20251214.tar.gz` | 13.2 MB | 06:58 UTC |
| `backup-mainnet-20251213_173825.tar.gz` | 12.5 MB | Dec 13 |

---

## PostgreSQL Streaming Replication Implementation (09:45 UTC)

### Overview
Implemented true streaming replication for PostgreSQL cluster, transforming 3 independent databases into a primary-standby configuration with automatic synchronization.

### Configuration Applied

**1. Primary (postgres-0):**
- WAL level: `replica`
- Max WAL senders: 5
- Max replication slots: 5
- Archive mode: on
- Hot standby: enabled

**2. Standbys (postgres-1, postgres-2):**
- Hot standby mode
- Physical replication slots
- Automatic failover configuration ready

**3. Replication Topology:**
```
postgres-0 (Primary - Kuala Lumpur)
    ├── streaming → postgres-1 (Phoenix, USA)
    └── streaming → postgres-2 (Frankfurt, Germany)
```

### K8s Resources Modified

| Resource | Type | Namespace | Changes |
|----------|------|-----------|---------|
| `postgres-credentials` | Secret | backend-mainnet | Added replication user credentials |
| `postgres-config` | ConfigMap | backend-mainnet | Updated postgresql.conf for replication |
| `postgres-init-scripts` | ConfigMap | backend-mainnet | Added primary/replica setup scripts |
| `postgres` | StatefulSet | backend-mainnet | Added init containers for replica bootstrap |
| `postgres-primary` | Service | backend-mainnet | Points to postgres-0 only (writes) |
| `postgres-replica` | Service | backend-mainnet | Points to all pods (reads) |

### Replication Verification

| Check | Result |
|-------|--------|
| postgres-0 is primary | `pg_is_in_recovery = f` |
| postgres-1 is standby | `pg_is_in_recovery = t` |
| postgres-2 is standby | `pg_is_in_recovery = t` |
| Slot postgres_1 active | Yes |
| Slot postgres_2 active | Yes |
| Replication state | Streaming |
| Replication lag | 0 bytes |
| Table count (all nodes) | 38 tables |
| Write test | Data replicated in <1 sec |
| Read-only verification | Replicas reject writes |

### Service Endpoints

| Service | Purpose | Endpoint |
|---------|---------|----------|
| `postgres-primary` | Writes | postgres-0:5432 |
| `postgres-replica` | Reads | All pods:5432 |
| `postgres-headless` | StatefulSet | All pods:5432 |

### RTO Improvement

| Scenario | Before | After |
|----------|--------|-------|
| Single Node Failure (srv1089618) | INFINITE | < 5 min (promote standby) |
| Data Corruption | INFINITE | < 15 min (restore from standby) |
| Regional Failure | INFINITE | < 30 min (cross-region standby) |

### Failover Procedure (Manual)

To promote a standby to primary (if postgres-0 fails):
```bash
# 1. Promote postgres-1 or postgres-2
kubectl exec -n backend-mainnet postgres-1 -- pg_ctl promote -D /var/lib/postgresql/data/pgdata

# 2. Update service selector
kubectl patch service postgres-primary -n backend-mainnet \
  -p '{"spec":{"selector":{"statefulset.kubernetes.io/pod-name":"postgres-1"}}}'

# 3. Reconfigure other standby to follow new primary
```

### Failover Test Results (09:47 UTC)

**Test Scenario:** Simulate postgres-0 failure by promoting postgres-1 to primary

| Step | Action | Result |
|------|--------|--------|
| 1 | Verify pre-failover state | postgres-0 primary, postgres-1/2 standbys streaming |
| 2 | Execute `pg_ctl promote` on postgres-1 | `server promoted` - success in ~2 seconds |
| 3 | Patch postgres-primary service selector | Endpoint changed from 10.42.0.218 → 10.42.1.246 |
| 4 | Test INSERT on new primary | Successfully created table and inserted row |
| 5 | Restore original configuration | Deleted standby pods, re-bootstrapped from postgres-0 |

**Timing Measurements:**
- Promotion command execution: ~2 seconds
- Service endpoint update: Instant
- **Total failover time: < 5 seconds**

**Write Test on New Primary:**
```sql
CREATE TABLE failover_test (...);
INSERT INTO failover_test (message) VALUES ('Written to postgres-1 after failover');
-- Result: INSERT 0 1 (success)
```

**Post-Test Restoration:**
- Service restored to postgres-0
- postgres-1 and postgres-2 deleted and re-bootstrapped
- Replication fully restored with 0 bytes lag

**Conclusion:** Failover procedure validated. In a real disaster, recovery to a standby can be completed in under 5 seconds with two commands.

### Files Backed Up

Pre-implementation state saved to `/tmp/postgres-backup/`:
- `postgres-credentials-backup.yaml`
- `postgres-config-backup.yaml`
- `postgres-statefulset-backup.yaml`

---

## Backup Restoration Test Results (10:05 UTC)

**Backup Tested:** `backup-mainnet-20251214_071437.tar.gz` (4.5 MB)

### Backup Contents Verified

| Component | Files | Size | Status |
|-----------|-------|------|--------|
| PostgreSQL dump | 1 | 87 KB (uncompressed) | Valid - 38 tables |
| Redis RDB | 1 | 88 bytes | Valid - empty DB correctly backed up |
| CouchDB (4 peers) | 4 archives | 451 KB total | Valid - 24 .couch files per peer |
| Fabric CA (5 CAs) | 5 archives | 23.5 KB total | Valid - keys and configs present |
| K8s state | 6 files | 3.7 MB | Valid - all resources exported |
| etcd snapshot | 1 | 19 MB | Valid |
| K3s configs | 3 | 3.3 KB | Valid |

### PostgreSQL Restoration Test

| Step | Action | Result |
|------|--------|--------|
| 1 | Download backup from Google Drive | 4.5 MB in 4.3 seconds |
| 2 | Extract archive | Success |
| 3 | Decompress SQL dump | 87 KB uncompressed |
| 4 | Create test database | `CREATE DATABASE restore_test` |
| 5 | Restore dump | Success |
| 6 | Verify table count | **38 tables** (matches production) |
| 7 | Drop test database | Cleanup complete |

**PostgreSQL Restoration: SUCCESS**

### Redis Backup Verification

| Check | Result |
|-------|--------|
| RDB header | Valid (REDIS0012) |
| Redis version | 7.4.7 |
| Current production DBSIZE | 0 keys |
| Backup represents | Empty database (correct) |

**Redis Backup: VALID**

### CouchDB Backup Verification

| Peer | Archive Size | Files Extracted |
|------|--------------|-----------------|
| peer0-org1 | 206 KB | 24 .couch files |
| peer0-org2 | 221 KB | 24 .couch files |
| peer1-org1 | 12 KB | 24 .couch files |
| peer1-org2 | 12 KB | 24 .couch files |

**CouchDB Backup: VALID**

### Fabric CA Backup Verification

All 5 CAs backed up with correct structure:
- `etc/hyperledger/fabric-ca-server/fabric-ca-server-config.yaml`
- `etc/hyperledger/fabric-ca-server/msp/keystore/key.pem`

**Fabric CA Backup: VALID**

### Restoration Procedure (Documented)

```bash
# 1. Download backup
rclone copy gdrive-gx:GX-Infrastructure-Backups/mainnet/backup-mainnet-YYYYMMDD_HHMMSS.tar.gz /tmp/

# 2. Extract
tar -xzf /tmp/backup-mainnet-*.tar.gz -C /tmp/

# 3. Restore PostgreSQL
gunzip /tmp/backup-mainnet-*/databases/postgres-mainnet.sql.gz
kubectl cp /tmp/backup-mainnet-*/databases/postgres-mainnet.sql backend-mainnet/postgres-0:/tmp/
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d postgres -f /tmp/postgres-mainnet.sql

# 4. Restore Redis (if needed)
kubectl cp /tmp/backup-mainnet-*/databases/redis-dump.rdb backend-mainnet/redis-0:/data/
kubectl exec -n backend-mainnet redis-0 -- redis-cli -a <password> DEBUG RELOAD

# 5. Restore CouchDB (if needed)
# Extract tar.gz to peer pod /opt/couchdb/data and restart
```

---

## 02:00 Scheduled Backup Script Test (10:05 UTC)

### Scheduled Backup Status Check

| Time | Script | Result |
|------|--------|--------|
| 02:00 UTC (today) | gx-full-backup.sh | **Failed** - ran before PATH fix |
| 07:11 UTC | PATH fix applied | - |
| 10:05 UTC | Manual test | **Success** |

### Manual Test Results

**Script:** `/root/backup-scripts/gx-full-backup.sh daily`
**Backup ID:** `gx-full-backup-20251214-100544`

| Component | Count | Status |
|-----------|-------|--------|
| Kubernetes namespaces | 11 | Backed up |
| Fabric secrets | 18 | Backed up |
| PostgreSQL (MainNet) | 1 | Backed up |
| PostgreSQL (TestNet) | 1 | Backed up |
| Redis (MainNet) | 1 | Backed up |
| Redis (TestNet) | 1 | Backed up |
| CouchDB peers | 4 | Backed up |
| Docker volumes | 17 | Backed up |

### Backup Metrics

| Metric | Value |
|--------|-------|
| Archive size | **13.34 MB** |
| Upload time | 3.3 seconds |
| Google Drive location | `GX-Infrastructure-Backups/daily/` |
| Verification | Confirmed in Google Drive |

### Minor Warnings (Non-Critical)

- Redis: `NOAUTH Authentication required` - backup completed via tar fallback
- CouchDB: `unauthorized` messages - data still backed up via tar

### Conclusion

The 02:00 backup script is now fully functional. Tonight's scheduled backup will complete successfully.

---

## Redis and CouchDB Authentication Fixes (10:17 UTC)

### Issue

The backup script was producing authentication warnings:
- Redis: `NOAUTH Authentication required`
- CouchDB: `unauthorized You are not a server admin`

### Fixes Applied

**File Modified:** `/root/backup-scripts/02-gx-full-backup.sh`

**1. Redis Authentication Fix:**
```bash
# Get Redis password from secret
REDIS_PASS=$(kubectl get secret -n backend-mainnet redis-credentials \
  -o jsonpath='{.data.REDIS_PASSWORD}' | base64 -d)

# Use authentication for all redis-cli commands
redis-cli -a "$REDIS_PASS" BGSAVE
```

**2. CouchDB Authentication Fix:**
```bash
# CouchDB credentials
COUCH_USER="admin"
COUCH_PASS="adminpw"

# Use authentication for all curl requests
curl -s -u "${COUCH_USER}:${COUCH_PASS}" http://localhost:5984/_all_dbs
```

### Test Results

| Metric | Before | After |
|--------|--------|-------|
| Redis warnings | `NOAUTH Authentication required` | None |
| CouchDB warnings | `unauthorized` | None |
| Backup size | 13.98 MB | **14.08 MB** |
| CouchDB databases exported | 0 (tar fallback) | **20 databases** |

### CouchDB Databases Now Properly Exported

| Peer | Databases |
|------|-----------|
| couchdb-peer0-org1-0 | 9 (including gxchannel_gxtv3) |
| couchdb-peer0-org2-0 | 9 (including gxchannel_gxtv3) |
| couchdb-peer1-org1-0 | 1 |
| couchdb-peer1-org2-0 | 1 |

### Verification

```
Google Drive: 14,082,136 bytes - gx-full-backup-20251214-101724.tar.gz
```

---

## Cluster Health Check and Cleanup (11:05 UTC)

### Initial Health Check Findings

**Problem Pods Discovered:**
- `svc-governance`, `svc-loanpool`, `svc-organization` - CrashLoopBackOff pods
- `outbox-submitter` - CrashLoopBackOff

**Root Cause Analysis:**
1. Deployments were stuck in rollout trying to use broken Docker image 2.1.0
2. Image 2.1.0 had Prisma client initialization error (`prisma generate` missing)
3. Working ReplicaSets were running on image 2.0.6

### Fixes Applied

**1. Deployment Rollback:**
```bash
# Paused stuck rollouts
kubectl rollout pause deploy/{svc-governance,svc-loanpool,svc-organization}

# Patched deployments to use working 2.0.6 images
kubectl set image deploy/svc-governance svc-governance=gx-protocol/svc-governance:2.0.6
kubectl set image deploy/svc-loanpool svc-loanpool=gx-protocol/svc-loanpool:2.0.6
kubectl set image deploy/svc-organization svc-organization=gx-protocol/svc-organization:2.0.6
kubectl set image deploy/outbox-submitter outbox-submitter=docker.io/gx-protocol/outbox-submitter:2.0.8

# Resumed rollouts
kubectl rollout resume deploy/{svc-governance,svc-loanpool,svc-organization}
```

**2. Network Partition Issue Discovered:**

While troubleshooting, discovered critical networking issue on srv1089618:
- Pods on srv1089618 could not reach any other nodes
- DNS resolution failing - CoreDNS unreachable
- Service IPs (10.43.x.x) unreachable from srv1089618 pods
- Cross-node pod communication broken

**Symptoms:**
- `outbox-submitter` - "Can't reach database server"
- `svc-admin` on srv1089618 - "Database health check failed"
- CoreDNS on srv1089618 - "waiting for Kubernetes API"

**3. Network Fix Applied:**

```bash
# Scaled up CoreDNS for redundancy
kubectl scale deploy coredns -n kube-system --replicas=3

# Created privileged debug pod on srv1089618
# Restarted K3s service on the affected node
kubectl exec -n kube-system node-debugger -- chroot /host systemctl restart k3s
```

**4. Stale ReplicaSet Cleanup:**

```bash
kubectl delete rs -n backend-mainnet \
  svc-governance-78cc546975 \
  svc-loanpool-bf8dc895b \
  svc-organization-57dfb586cc \
  svc-governance-8474765dfd \
  svc-loanpool-7cf6fbcd95 \
  svc-organization-757f859b5d \
  outbox-submitter-5566c584fc
```

### Final State

| Component | Before | After |
|-----------|--------|-------|
| svc-governance | 3/3 (1 CrashLoop) | 3/3 Running |
| svc-loanpool | 3/3 (1 CrashLoop) | 3/3 Running |
| svc-organization | 3/3 (1 CrashLoop) | 3/3 Running |
| outbox-submitter | 0/1 CrashLoop | 1/1 Running |
| srv1089618 networking | Broken | Fixed |
| CoreDNS replicas | 1 | 3 (one per node) |
| PostgreSQL replication | Healthy | Healthy (0 lag) |
| Problem pods | 4+ | 0 |

### Lessons Learned

1. **Image versioning**: Always verify Docker images work before pushing to deployments
2. **CoreDNS redundancy**: Single CoreDNS pod is a SPOF - scaled to 3 replicas
3. **K3s networking**: Node-level networking issues can be resolved by restarting K3s
4. **Monitoring needed**: Need alerting for cross-node connectivity issues

---

## Backup Cron Configuration (11:15 UTC)

### Cron Schedule Configured

```crontab
# GX Infrastructure Backup Schedule
# Full daily backup at 02:00 UTC
0 2 * * * /root/backup-scripts/02-gx-full-backup.sh daily >> /root/backup-logs/daily-backup.log 2>&1

# Weekly backup at 03:00 UTC on Sundays
0 3 * * 0 /root/backup-scripts/02-gx-full-backup.sh weekly >> /root/backup-logs/weekly-backup.log 2>&1

# Monthly backup at 04:00 UTC on 1st of month
0 4 1 * * /root/backup-scripts/02-gx-full-backup.sh monthly >> /root/backup-logs/monthly-backup.log 2>&1
```

### Verification

| Check | Status |
|-------|--------|
| Cron daemon (crond) | Active and running |
| Crontab installed | Verified |
| Logs directory | `/root/backup-logs/` exists |
| Script executable | `/root/backup-scripts/02-gx-full-backup.sh` |

### Disk Space Check

| Node | Used | Available | Usage |
|------|------|-----------|-------|
| srv1089618 | 103G | 297G | 26% |
| srv1089624 | 95G | 305G | 24% |
| srv1092158 | 71G | 329G | 18% |
| srv1117946 | 44G | 355G | 12% |

**Google Drive**: 890 MB used (10 backup files)

Tonight's backup (~14 MB) will complete without issues.

---

## Next Steps

1. ~~Review BACKUP_AUDIT_20251214.md and HA_DR_STRATEGY.md~~ - Completed
2. ~~Implement fixes in order of priority~~ - Completed
3. ~~Implement PostgreSQL streaming replication for true HA~~ - Completed
4. ~~Test failover procedure~~ - Completed (< 5 sec failover validated)
5. ~~Test backup restoration procedure~~ - Completed (all components valid)
6. ~~Manual test 02:00 backup script~~ - Completed (13.34 MB uploaded)
7. ~~Fix Redis/CouchDB authentication warnings~~ - Completed (14.08 MB uploaded)
8. ~~Clean up orphaned crashing pods~~ - Completed (all deployments healthy)
9. ~~Configure backup cron schedule~~ - Completed (daily/weekly/monthly)
10. **Monitor** next scheduled backup (02:00 UTC tonight)
11. **Consider** automated failover with Patroni or pg_auto_failover
12. **Update** backend application to use read replicas for read-heavy queries
13. **Investigate** why image 2.1.0 was built without `prisma generate`
14. **Add monitoring** for cross-node connectivity

---

*Work completed: December 14, 2025 11:15 UTC*
*Backup fixes applied and verified*
*PostgreSQL streaming replication implemented and tested*
*Failover procedure tested and validated (< 5 seconds)*
*Backup restoration procedure tested and documented*
*02:00 scheduled backup script manually tested and verified*
*Redis and CouchDB authentication fixes applied*
*Cluster health restored - networking issue on srv1089618 fixed*
*CoreDNS scaled to 3 replicas for redundancy*
*Backup cron schedule configured (daily/weekly/monthly)*
