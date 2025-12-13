# GX Coin Protocol Backup Strategy

**Version:** 1.0
**Created:** December 13, 2025
**Status:** PENDING IMPLEMENTATION

---

## Overview

This document defines the comprehensive backup strategy for all GX Coin Protocol infrastructure components, extending the existing PostgreSQL/Redis backup system to cover all 5 servers with Google Drive as the backup destination.

---

## Backup Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          BACKUP ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐      │
│  │   VPS-1     │  │   VPS-2     │  │  VPS-3, VPS-4, VPS-5       │      │
│  │  Website    │  │  Dev/Test   │  │  MainNet Cluster            │      │
│  └──────┬──────┘  └──────┬──────┘  └───────────────┬─────────────┘      │
│         │                │                         │                     │
│         ▼                ▼                         ▼                     │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                     rclone (SFTP/HTTP API)                      │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                  │                                       │
│                                  ▼                                       │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                        Google Drive                             │     │
│  │  gdrive-backup:/gx-backups/                                    │     │
│  │  ├── vps1-website/                                             │     │
│  │  │   └── YYYYMMDD_HHMMSS/                                      │     │
│  │  ├── vps2-devtest/                                             │     │
│  │  │   └── YYYYMMDD_HHMMSS/                                      │     │
│  │  └── mainnet/                                                  │     │
│  │      └── YYYYMMDD_HHMMSS/                                      │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Backup Categories

### 1. Application Data

| Data Type | Location | Backup Method | Frequency | Retention |
|-----------|----------|---------------|-----------|-----------|
| Website Files | VPS-1:/var/www/gxcoin.money | tar + rclone | Daily | 30 days |
| Docker Compose Config | VPS-3:/root/fabric/ | tar + rclone | Daily | 90 days |
| K8s Manifests | All servers | kubectl export | Daily | 90 days |

### 2. Database Data

| Database | Location | Backup Method | Frequency | Retention |
|----------|----------|---------------|-----------|-----------|
| PostgreSQL (MainNet) | K8s backend-mainnet | pg_dump + K8s CronJob | 6 hours | 7 days |
| PostgreSQL (TestNet) | K8s backend-testnet | pg_dump + K8s CronJob | 6 hours | 3 days |
| Redis (MainNet) | K8s backend-mainnet | BGSAVE + K8s CronJob | 6 hours | 7 days |
| Redis (TestNet) | K8s backend-testnet | BGSAVE + K8s CronJob | 6 hours | 3 days |
| CouchDB (Fabric) | K8s fabric namespace | HTTP API backup | Daily | 30 days |
| CA PostgreSQL | Docker/K8s | pg_dump | Daily | 90 days |

### 3. Blockchain Data

| Data Type | Location | Backup Method | Frequency | Retention |
|-----------|----------|---------------|-----------|-----------|
| Fabric Crypto Materials | K8s secrets/PVCs | kubectl cp | Daily | 90 days |
| Orderer Ledger | K8s fabric namespace | PVC snapshot | Daily | 30 days |
| Peer Ledger | K8s fabric namespace | PVC snapshot | Daily | 30 days |
| Chaincode Packages | K8s fabric namespace | kubectl cp | Weekly | 90 days |

### 4. System Configuration

| Config Type | Location | Backup Method | Frequency | Retention |
|-------------|----------|---------------|-----------|-----------|
| K3s Config | /etc/rancher/k3s | tar + rclone | Daily | 90 days |
| etcd Snapshots | K3s automatic | rclone sync | Daily | 30 days |
| SSH Keys | /root/.ssh | tar + rclone | Weekly | 90 days |
| System Configs | /etc/ | tar + rclone | Weekly | 90 days |

---

## Implementation Details

### rclone Configuration

**Installation (on all servers):**
```bash
curl https://rclone.org/install.sh | bash
```

**Google Drive Remote Configuration:**
```bash
rclone config

# Interactive setup:
# Name: gdrive-backup
# Storage: drive
# Client ID: [use default]
# Client Secret: [use default]
# Scope: drive
# Root folder ID: [leave blank]
# Service Account: [leave blank]
# Advanced config: No
# Auto config: Yes (follow OAuth flow)
```

**Verification:**
```bash
rclone lsd gdrive-backup:
rclone mkdir gdrive-backup:gx-backups
```

---

## Backup Scripts

### VPS-1: Website Backup Script

**Location:** `/root/scripts/backup-vps1.sh`

```bash
#!/bin/bash
#
# VPS-1 Website Backup Script
# Backs up website files and K8s configurations to Google Drive
#

set -euo pipefail

# Configuration
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup-vps1-${BACKUP_DATE}"
REMOTE="gdrive-backup:gx-backups/vps1-website"
LOG_FILE="/var/log/backup-vps1.log"
RETENTION_DAYS=30

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

# Error handler
error_exit() {
    log "ERROR: $1"
    rm -rf ${BACKUP_DIR}
    exit 1
}

# Start backup
log "Starting VPS-1 backup..."
mkdir -p ${BACKUP_DIR}

# 1. Backup website files
log "Backing up website files..."
tar -czf ${BACKUP_DIR}/website.tar.gz -C /var/www gxcoin.money 2>/dev/null || error_exit "Failed to backup website"

# 2. Backup Docker container state
log "Backing up Docker state..."
docker ps -a --format '{{json .}}' > ${BACKUP_DIR}/docker-containers.json
docker images --format '{{json .}}' > ${BACKUP_DIR}/docker-images.json

# 3. Backup K3s manifests
log "Backing up K8s configurations..."
kubectl get all -A -o yaml > ${BACKUP_DIR}/k8s-all-resources.yaml 2>/dev/null || log "Warning: kubectl export failed"
kubectl get secrets -A -o yaml > ${BACKUP_DIR}/k8s-secrets.yaml 2>/dev/null || true
kubectl get configmaps -A -o yaml > ${BACKUP_DIR}/k8s-configmaps.yaml 2>/dev/null || true
kubectl get pvc -A -o yaml > ${BACKUP_DIR}/k8s-pvcs.yaml 2>/dev/null || true

# 4. Backup K3s configuration
log "Backing up K3s config..."
cp /etc/rancher/k3s/k3s.yaml ${BACKUP_DIR}/ 2>/dev/null || true

# 5. Upload to Google Drive
log "Uploading to Google Drive..."
rclone copy ${BACKUP_DIR} ${REMOTE}/${BACKUP_DATE}/ --progress --log-file=${LOG_FILE} || error_exit "rclone upload failed"

# 6. Cleanup local backup
log "Cleaning up local files..."
rm -rf ${BACKUP_DIR}

# 7. Apply retention policy
log "Applying retention policy (${RETENTION_DAYS} days)..."
rclone delete ${REMOTE} --min-age ${RETENTION_DAYS}d --log-file=${LOG_FILE}

# 8. Verify backup exists
log "Verifying backup..."
rclone lsl ${REMOTE}/${BACKUP_DATE}/ | head -5

log "VPS-1 backup completed successfully"
```

### VPS-2: DevNet/TestNet Backup Script

**Location:** `/root/scripts/backup-vps2.sh`

```bash
#!/bin/bash
#
# VPS-2 DevNet/TestNet Backup Script
#

set -euo pipefail

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup-vps2-${BACKUP_DATE}"
REMOTE="gdrive-backup:gx-backups/vps2-devtest"
LOG_FILE="/var/log/backup-vps2.log"
RETENTION_DAYS=14  # Shorter retention for dev/test

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

log "Starting VPS-2 backup..."
mkdir -p ${BACKUP_DIR}/{devnet,testnet,configs}

# 1. Backup K8s resources
log "Backing up K8s resources..."
for ns in fabric-devnet fabric-testnet backend-devnet backend-testnet; do
    kubectl get all -n ${ns} -o yaml > ${BACKUP_DIR}/${ns}-resources.yaml 2>/dev/null || true
done

# 2. Backup TestNet PostgreSQL
log "Backing up TestNet PostgreSQL..."
kubectl exec -n backend-testnet postgres-0 -- pg_dumpall -U postgres > ${BACKUP_DIR}/testnet/postgres.sql 2>/dev/null || log "PostgreSQL backup skipped"

# 3. Backup TestNet Fabric crypto (if exists)
log "Backing up TestNet Fabric crypto..."
kubectl get secrets -n fabric-testnet -o yaml > ${BACKUP_DIR}/testnet/fabric-secrets.yaml 2>/dev/null || true

# 4. Backup K3s config
log "Backing up K3s config..."
cp /etc/rancher/k3s/k3s.yaml ${BACKUP_DIR}/configs/ 2>/dev/null || true

# 5. Upload
log "Uploading to Google Drive..."
rclone copy ${BACKUP_DIR} ${REMOTE}/${BACKUP_DATE}/ --progress --log-file=${LOG_FILE}

# 6. Cleanup
rm -rf ${BACKUP_DIR}

# 7. Retention
rclone delete ${REMOTE} --min-age ${RETENTION_DAYS}d --log-file=${LOG_FILE}

log "VPS-2 backup completed successfully"
```

### VPS-3: MainNet Primary Backup Script

**Location:** `/root/scripts/backup-mainnet.sh`

```bash
#!/bin/bash
#
# MainNet Primary Backup Script (runs on VPS-3)
# Comprehensive backup of all MainNet components
#

set -euo pipefail

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup-mainnet-${BACKUP_DATE}"
REMOTE="gdrive-backup:gx-backups/mainnet"
LOG_FILE="/var/log/backup-mainnet.log"
RETENTION_DAYS=30

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

error_exit() {
    log "ERROR: $1"
    rm -rf ${BACKUP_DIR}
    exit 1
}

log "Starting MainNet backup..."
mkdir -p ${BACKUP_DIR}/{fabric-crypto,databases,k8s-state,etcd}

# 1. Backup Fabric Certificate Authority data
log "Backing up Certificate Authorities..."
for ca in ca-root-0 ca-org1-0 ca-org2-0 ca-orderer-0 ca-tls-0; do
    POD=$(kubectl get pod -n fabric -l app=${ca%-0} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD" ]; then
        kubectl exec -n fabric ${POD} -- tar -cf - /var/hyperledger 2>/dev/null | gzip > ${BACKUP_DIR}/fabric-crypto/${ca}.tar.gz || log "Warning: ${ca} backup failed"
    fi
done

# 2. Backup Fabric secrets (crypto materials)
log "Backing up Fabric secrets..."
kubectl get secrets -n fabric -o yaml > ${BACKUP_DIR}/fabric-crypto/fabric-secrets.yaml

# 3. Backup PostgreSQL (MainNet Backend)
log "Backing up MainNet PostgreSQL..."
kubectl exec -n backend-mainnet postgres-0 -- pg_dumpall -U postgres > ${BACKUP_DIR}/databases/postgres-mainnet.sql 2>/dev/null || log "Warning: PostgreSQL backup failed"

# 4. Backup PostgreSQL (CA Database)
log "Backing up CA PostgreSQL..."
# If running in Docker Compose
docker exec postgres.ca pg_dumpall -U postgres > ${BACKUP_DIR}/databases/postgres-ca.sql 2>/dev/null || true
# If running in K8s
kubectl exec -n fabric postgres-0 -- pg_dumpall -U postgres >> ${BACKUP_DIR}/databases/postgres-ca.sql 2>/dev/null || true

# 5. Backup Redis RDB snapshot
log "Backing up Redis..."
kubectl exec -n backend-mainnet redis-0 -- redis-cli BGSAVE
sleep 5
kubectl cp backend-mainnet/redis-0:/data/dump.rdb ${BACKUP_DIR}/databases/redis-dump.rdb 2>/dev/null || true

# 6. Backup all K8s resources
log "Backing up K8s state..."
kubectl get all -A -o yaml > ${BACKUP_DIR}/k8s-state/all-resources.yaml
kubectl get secrets -A -o yaml > ${BACKUP_DIR}/k8s-state/secrets.yaml
kubectl get configmaps -A -o yaml > ${BACKUP_DIR}/k8s-state/configmaps.yaml
kubectl get pvc -A -o yaml > ${BACKUP_DIR}/k8s-state/pvcs.yaml
kubectl get pv -o yaml > ${BACKUP_DIR}/k8s-state/pvs.yaml
kubectl get crd -o yaml > ${BACKUP_DIR}/k8s-state/crds.yaml

# 7. Backup etcd snapshot
log "Creating etcd snapshot..."
kubectl exec -n kube-system -l component=etcd -- etcdctl snapshot save /tmp/etcd-snapshot.db 2>/dev/null || true
# K3s automatic snapshots
cp /var/lib/rancher/k3s/server/db/etcd-backup-* ${BACKUP_DIR}/etcd/ 2>/dev/null || true

# 8. Backup K3s server token and config
log "Backing up K3s configuration..."
cp /var/lib/rancher/k3s/server/node-token ${BACKUP_DIR}/etcd/ 2>/dev/null || true
cp /etc/rancher/k3s/k3s.yaml ${BACKUP_DIR}/etcd/

# 9. Upload to Google Drive
log "Uploading to Google Drive..."
rclone copy ${BACKUP_DIR} ${REMOTE}/${BACKUP_DATE}/ --progress --log-file=${LOG_FILE} || error_exit "rclone upload failed"

# 10. Cleanup
log "Cleaning up local files..."
rm -rf ${BACKUP_DIR}

# 11. Apply retention policy
log "Applying retention policy..."
rclone delete ${REMOTE} --min-age ${RETENTION_DAYS}d --log-file=${LOG_FILE}

# 12. Verify
log "Verifying backup..."
BACKUP_SIZE=$(rclone size ${REMOTE}/${BACKUP_DATE}/ --json | jq -r '.bytes')
log "Backup size: ${BACKUP_SIZE} bytes"

log "MainNet backup completed successfully"
```

---

## Cron Schedule

### VPS-1 Crontab
```cron
# Backup at 2:00 AM daily
0 2 * * * /root/scripts/backup-vps1.sh >> /var/log/backup-vps1.log 2>&1
```

### VPS-2 Crontab
```cron
# Backup at 3:00 AM daily
0 3 * * * /root/scripts/backup-vps2.sh >> /var/log/backup-vps2.log 2>&1
```

### VPS-3 Crontab (MainNet Primary)
```cron
# Full backup at 4:00 AM daily
0 4 * * * /root/scripts/backup-mainnet.sh >> /var/log/backup-mainnet.log 2>&1

# Incremental backup every 6 hours
0 */6 * * * /root/scripts/backup-mainnet-incremental.sh >> /var/log/backup-mainnet-incr.log 2>&1
```

---

## Existing K8s Backup Jobs (Retain)

The existing Kubernetes CronJobs for PostgreSQL and Redis should be retained:

```yaml
# backend-mainnet namespace
CronJob: postgres-backup    # Every 6 hours
CronJob: redis-backup       # Every 6 hours
```

These provide local/cluster-level backups. The rclone scripts provide off-site (Google Drive) backups.

---

## Recovery Procedures

### Restore Website (VPS-1)

```bash
# 1. List available backups
rclone lsd gdrive-backup:gx-backups/vps1-website/

# 2. Download specific backup
BACKUP_DATE="20251213_020000"
rclone copy gdrive-backup:gx-backups/vps1-website/${BACKUP_DATE}/ /tmp/restore/

# 3. Restore website files
cd /var/www
tar -xzf /tmp/restore/website.tar.gz

# 4. Restart services
docker restart gxcoin-app-green
```

### Restore MainNet PostgreSQL

```bash
# 1. Download backup
rclone copy gdrive-backup:gx-backups/mainnet/YYYYMMDD_HHMMSS/databases/postgres-mainnet.sql /tmp/

# 2. Restore to PostgreSQL
kubectl cp /tmp/postgres-mainnet.sql backend-mainnet/postgres-0:/tmp/
kubectl exec -n backend-mainnet postgres-0 -- psql -U postgres -f /tmp/postgres-mainnet.sql
```

### Restore Fabric Crypto Materials

```bash
# 1. Download CA backup
rclone copy gdrive-backup:gx-backups/mainnet/YYYYMMDD_HHMMSS/fabric-crypto/ /tmp/restore/

# 2. Restore to CA pod
kubectl cp /tmp/restore/ca-root-0.tar.gz fabric/ca-root-0:/tmp/
kubectl exec -n fabric ca-root-0 -- tar -xzf /tmp/ca-root-0.tar.gz -C /
```

### Restore K3s Cluster (Disaster Recovery)

```bash
# 1. Download etcd snapshot
rclone copy gdrive-backup:gx-backups/mainnet/YYYYMMDD_HHMMSS/etcd/ /tmp/restore/

# 2. Reset K3s with snapshot
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/tmp/restore/etcd-backup-TIMESTAMP

# 3. Rejoin other nodes
# On VPS-4 and VPS-5:
systemctl restart k3s
```

---

## Monitoring & Alerting

### Backup Success Monitoring

Add to Prometheus alerts:
```yaml
- alert: BackupJobFailed
  expr: time() - backup_last_success_timestamp > 86400
  for: 1h
  labels:
    severity: critical
  annotations:
    summary: "Backup job has not succeeded in 24 hours"
```

### Log Monitoring

Add to Loki queries:
```
{filename="/var/log/backup-*.log"} |= "ERROR"
```

### Health Check Script

```bash
#!/bin/bash
# /root/scripts/check-backup-health.sh

REMOTE="gdrive-backup:gx-backups"

for dir in vps1-website vps2-devtest mainnet; do
    LATEST=$(rclone lsd ${REMOTE}/${dir}/ --max-depth 1 | tail -1 | awk '{print $5}')
    AGE=$(( ($(date +%s) - $(date -d ${LATEST:0:8} +%s)) / 86400 ))

    if [ $AGE -gt 1 ]; then
        echo "WARNING: ${dir} backup is ${AGE} days old"
    else
        echo "OK: ${dir} last backup: ${LATEST}"
    fi
done
```

---

## Testing Schedule

| Test Type | Frequency | Description |
|-----------|-----------|-------------|
| Backup Verification | Daily | Check backup job completed |
| Restore Test (Non-prod) | Weekly | Test restore to dev environment |
| Full DR Test | Monthly | Complete disaster recovery simulation |
| Backup Integrity | Weekly | Verify backup file checksums |

---

*End of Backup Strategy Document*
