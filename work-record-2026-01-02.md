# Work Record - 2026-01-02

## Summary
Infrastructure recovery for DevNet and TestNet environments after VPS4 toleration issues. All services restored to operational status.

---

## Issues Identified and Fixed

### 1. DevNet Redis StatefulSet - VPS4 Toleration Missing

**Problem:** Redis pod stuck in Pending state.

**Root Cause:**
- Redis StatefulSet had `nodeSelector: node-id=vps4`
- VPS4 (srv1089624 / 217.196.51.190) has `environment=nonprod:NoSchedule` taint
- Old PVC was bound to wrong node (srv1117946 / vps2)
- StatefulSet lacked toleration for nonprod taint

**Fix Applied:**
1. Deleted old StatefulSet and PVC
2. Recreated StatefulSet with:
   - `nodeSelector: node-id: vps4`
   - `tolerations: [{key: "environment", operator: "Equal", value: "nonprod", effect: "NoSchedule"}]`
   - Fixed secret key reference (`REDIS_PASSWORD` instead of `password`)
3. New PVC created on correct node (VPS4)

---

### 2. DevNet Postgres Connection Failure

**Problem:** All backend services crashing with Prisma error P1000 (authentication failed).

**Root Cause:**
- ConfigMap `backend-config` had `DATABASE_URL` with password `DevnetPass2025`
- Actual postgres password was `devnet_password_123`
- User `gx_backend` referenced in some configs didn't exist

**Fix Applied:**
1. Updated `backend-config` ConfigMap with correct password
2. Updated `backend-secrets` Secret with correct DATABASE_PASSWORD
3. Created `gx_backend` user with appropriate privileges
4. Ran `prisma db push` to ensure schema is current
5. Restarted all deployments

**Result:** All DevNet services now running.

---

### 3. TestNet Infrastructure Recovery

**Problem:** Postgres, Redis, and Minio pods stuck in Pending state.

**Root Cause:**
- Old PVCs were bound to srv1117946 (vps2) from previous misconfiguration
- StatefulSets had `nodeSelector: node-id=vps4` but lacked nonprod toleration
- PV node affinity conflicted with pod node selector

**Fix Applied:**
1. Deleted all three StatefulSets (postgres, redis, minio)
2. Deleted all associated PVCs
3. Recreated StatefulSets with:
   - Proper VPS4 tolerations
   - Correct secret key references
4. New PVCs created on VPS4 (srv1089624)
5. Updated postgres password to match service expectations
6. Ran `prisma db push` to create schema
7. Restarted backend deployments

**Result:** All TestNet services now running.

---

## VPS Mapping Reference (Authoritative)

| VPS | Hostname | IP Address | Role | Taint |
|-----|----------|------------|------|-------|
| VPS1 | srv1089618 | 72.60.210.201 | MainNet | none |
| VPS2 | srv1117946 | 72.61.116.210 | MainNet | none |
| VPS3 | srv1092158 | 72.61.81.3 | MainNet | none |
| **VPS4** | **srv1089624** | **217.196.51.190** | **DevNet/TestNet** | **environment=nonprod:NoSchedule** |

---

## Current Cluster Status

### DevNet (backend-devnet namespace)
| Service | Status | Notes |
|---------|--------|-------|
| postgres-0 | Running | VPS4 |
| redis-0 | Running | VPS4 |
| minio | Running | VPS4 |
| svc-identity | Running | |
| svc-tokenomics | Running | |
| svc-admin | Running | |
| svc-messaging | Running | |
| svc-governance | Running | |
| svc-loanpool | Running | |
| svc-organization | Running | |
| svc-tax | Running | |
| projector | Running | |
| outbox-submitter | Running | |

### TestNet (backend-testnet namespace)
| Service | Status | Notes |
|---------|--------|-------|
| postgres-0 | Running | VPS4 |
| redis-0 | Running | VPS4 |
| minio-0 | Running | VPS4 |
| svc-identity | Running | |
| svc-tokenomics | Running | |
| svc-admin | Running | |
| svc-messaging | Running | |
| svc-governance | Running | |
| svc-loanpool | Running | |
| svc-organization | Running | |
| svc-tax | Running | |
| projector | Running | |
| outbox-submitter | Running | |

### MainNet (backend-mainnet namespace)
- All services operational (no issues identified)

---

## Key Configuration Details

### DevNet
- **Database URL:** `postgresql://gx_admin:devnet_password_123@postgres-primary.backend-devnet.svc.cluster.local:5432/gx_protocol`
- **Redis Secret Key:** `REDIS_PASSWORD`

### TestNet
- **Database URL:** `postgresql://gx_admin:TestnetPass2025@postgres-primary.backend-testnet.svc.cluster.local:5432/gx_protocol`
- **Redis Secret Key:** `password`

---

## Commands Reference

```bash
# Check non-running pods
kubectl get pods -A --no-headers | grep -v Running | grep -v Completed

# Add nonprod toleration to a StatefulSet
kubectl patch statefulset <name> -n <namespace> --type='strategic' -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"environment","operator":"Equal","value":"nonprod","effect":"NoSchedule"}]}}}}'

# Run prisma db push
cd /home/sugxcoin/prod-blockchain/gx-protocol-backend
DATABASE_URL="<url>" ./node_modules/.bin/prisma db push --schema=db/prisma/schema.prisma --skip-generate
```

---

## Lessons Learned

1. **StatefulSet PVCs are node-bound** - When using local-path provisioner, PVCs are bound to specific nodes. Moving a StatefulSet to a different node requires deleting and recreating the PVC.

2. **Tolerations must match taints** - All pods targeting VPS4 must include the `environment=nonprod:NoSchedule` toleration.

3. **Credential consistency is critical** - ConfigMaps, Secrets, and actual database passwords must all match.

---

## Date: 2026-01-02
## Status: All Environments Operational
