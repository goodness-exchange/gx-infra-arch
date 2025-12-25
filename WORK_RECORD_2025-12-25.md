# Work Record - December 25, 2025

## Summary
Deployed messaging infrastructure to MainNet, including MinIO S3 storage, database schema, ingress configuration, and frontend update.

---

## Tasks Completed

### 1. MainNet Messaging Backend Deployment

#### MinIO S3 Storage
- Deployed MinIO StatefulSet with 50GB persistent storage
- Created `gx-voice-messages` bucket for file attachments
- Configured credentials: `gxmainnet` / `GxMainNet2025S3SecureStorage`

#### svc-messaging Service Update
- Updated image to `conv-fix` tag with conversation creation fix
- Added S3 environment variables:
  - `S3_ENDPOINT=http://minio.backend-mainnet.svc.cluster.local:9000`
  - `S3_BUCKET_VOICE=gx-voice-messages`
  - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- Added `tier: api` label for NetworkPolicy

#### Database Schema
- Created messaging tables directly via SQL (Prisma not accessible from pods):
  - `Conversation` - Chat containers
  - `ConversationParticipant` - User membership
  - `Message` - Encrypted messages with file attachment support
  - `MessageDeliveryReceipt` - Delivery tracking
  - `UserSignalKey` - E2E encryption identity keys
  - `SignalPreKey` - One-time pre-keys
  - `GroupEncryptionKey` - Group chat symmetric keys
  - `GroupParticipantKey` - Per-participant wrapped keys
- Created enums: `ConversationType`, `ParticipantRole`, `MessageType`, `MessageStatus`

#### Ingress Configuration
- Added WebSocket annotations for Socket.io support
- Added messaging routes:
  - `/socket.io` - Real-time WebSocket
  - `/api/v1/conversations` - Conversation management
  - `/api/v1/messages` - Message send/receive
  - `/api/v1/files` - File upload/download proxy
  - `/api/v1/voice` - Voice messages
  - `/api/v1/keys` - Encryption keys
  - `/api/v1/groups` - Group management

#### Network Policy
- Updated `allow-ingress-to-services` to include ports 3007 and 3008

---

### 2. MainNet Frontend Update

- Built frontend with mainnet configuration:
  - `NEXT_PUBLIC_API_URL=https://api.gxcoin.money`
  - `NEXT_PUBLIC_WS_URL=wss://api.gxcoin.money`
- Tagged as `mainnet-messaging`
- Deployed to `gx-wallet-frontend` deployment
- Added `tier: api` label for NetworkPolicy access

---

### 3. Verification

#### Endpoint Status
| Endpoint | Status |
|----------|--------|
| Socket.io | Working (WebSocket upgrades available) |
| /api/v1/conversations | 401 (auth protected) |
| /api/v1/messages | 401 (auth protected) |
| /api/v1/files | 401 (auth protected) |
| /api/v1/voice | 401 (auth protected) |
| /api/v1/keys | 401 (auth protected) |
| /api/v1/groups | 401 (auth protected) |

#### Frontend Pages
| Page | Status |
|------|--------|
| Landing (/) | 200 OK |
| Login (/login) | 200 OK |
| Messages (/messages) | 307 Redirect (to login) |

#### E2E Test
- Created test users for browser testing
- Created conversation between users
- Sent test message
- Uploaded test file
- All operations successful

---

### 4. Infrastructure Commits

**Repository:** gx-infra-arch

**Commit:** `daba1a9`
```
feat(mainnet): add messaging infrastructure manifests

- k8s/mainnet/messaging/minio.yaml
- k8s/mainnet/messaging/ingress.yaml
- k8s/mainnet/messaging/network-policy.yaml
- k8s/mainnet/messaging/database-schema.sql
- k8s/mainnet/messaging/README.md
```

---

## MainNet URLs

| Service | URL |
|---------|-----|
| Wallet Frontend | https://wallet.gxcoin.money |
| API | https://api.gxcoin.money |
| WebSocket | wss://api.gxcoin.money/socket.io |

---

## Browser Test Credentials

| User | Email | Password |
|------|-------|----------|
| Alice | mainnet_msg_1766642581@gxcoin.test | TestPass123 |
| Bob | mainnet_msg2_1766642581@gxcoin.test | TestPass123 |

---

## Issues Encountered & Solutions

### Issue 1: Database Schema Push Failed
- **Problem:** Prisma CLI couldn't connect from local machine, and production pods don't have schema files
- **Solution:** Created SQL script and executed directly via `kubectl exec` to postgres pod

### Issue 2: Frontend 502 Bad Gateway
- **Problem:** NetworkPolicy blocking ingress traffic to frontend pods
- **Solution:** Added `tier: api` label to frontend deployment

### Issue 3: Port-forward Connection Issues
- **Problem:** Port-forward to postgres kept failing with access denied
- **Solution:** Used `kubectl exec` directly to postgres pod instead

### Issue 4: Redis Authentication Failure (CRITICAL)
- **Problem:** svc-messaging was configured with testnet Redis password instead of mainnet password
- **Symptoms:** Continuous Redis auth errors in logs:
  ```
  Redis connection error in MessageRelayService
  Redis pub client error
  Redis error in VoiceRelayService
  Presence Redis client error, using in-memory store
  ```
- **Root Cause:** REDIS_URL env var had wrong password:
  ```
  Wrong: redis://:Vqgag%2Fj9zz6pb5mXSfSNY0C%2FQt86zPojErs43Zq7vMA%3D@redis-master...
  ```
- **Solution:** Updated REDIS_URL to use correct mainnet password:
  ```bash
  kubectl set env deployment/svc-messaging -n backend-mainnet \
    REDIS_URL="redis://:XRCwgQQGOOH998HxD9XH24oJbjdHPPxl@redis-master.backend-mainnet.svc.cluster.local:6379"
  ```
- **Verification:** All Redis errors cleared, real-time features working

---

## Files Modified/Created

### gx-infra-arch
- `k8s/mainnet/messaging/minio.yaml` (NEW)
- `k8s/mainnet/messaging/ingress.yaml` (NEW)
- `k8s/mainnet/messaging/network-policy.yaml` (NEW)
- `k8s/mainnet/messaging/database-schema.sql` (NEW)
- `k8s/mainnet/messaging/README.md` (NEW)
- `k8s/mainnet/messaging/svc-messaging-env.yaml` (NEW) - Environment configuration

---

### 5. Redis Configuration Verification (All Environments)

Verified Redis configuration across all environments after fixing MainNet:

| Environment | Redis Password Secret | svc-messaging REDIS_URL | Status |
|------------|----------------------|------------------------|--------|
| DevNet | redis-secret.REDIS_PASSWORD = `RedisDevnet2025` | `redis://:RedisDevnet2025@redis-master.backend-devnet...` | ✅ Correct |
| TestNet | redis-secret.password = `Vqgag/j9...` | `redis://:Vqgag%2F...@redis-master.backend-testnet...` | ✅ Correct |
| MainNet | redis-credentials.REDIS_PASSWORD = `XRCwgQQGOOH998...` | `redis://:XRCwgQQGOOH998...@redis-master.backend-mainnet...` | ✅ Correct (Fixed) |

All environments verified with no Redis errors in logs.

### 6. TestNet redis-secret Fix

Fixed stale `redis-url` in testnet redis-secret that was incorrectly pointing to mainnet:

- **Before:** `redis://:...@redis-master.backend-mainnet.svc.cluster.local:6379`
- **After:** `redis://:...@redis-master.backend-testnet.svc.cluster.local:6379`

```bash
kubectl patch secret redis-secret -n backend-testnet --type='json' \
  -p='[{"op": "replace", "path": "/data/redis-url", "value": "<base64-encoded-correct-url>"}]'
```

### 7. MinIO Credentials Secrets Setup

Created proper Kubernetes secrets for MinIO credentials across all environments:

#### Secrets Created
| Environment | Secret Name | Keys |
|-------------|-------------|------|
| DevNet | minio-credentials | MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY |
| TestNet | minio-credentials | MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY |
| MainNet | minio-credentials | MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY |

#### MinIO Updates
- Patched MinIO deployment/statefulset in all environments to use secretKeyRef
- Removed hardcoded MINIO_ROOT_USER and MINIO_ROOT_PASSWORD values

#### svc-messaging Updates
- Removed hardcoded AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
- Added secretKeyRef to minio-credentials secret

#### Verification
- All services rolled out successfully
- Health checks passing on all environments

### 8. MinIO Backup Configuration

Configured automated backups for MinIO S3 storage across all environments:

#### Backup Schedule
| Environment | Schedule | Retention | Storage |
|-------------|----------|-----------|---------|
| DevNet | Every 6h (:30) | 7 days | 10Gi PVC |
| TestNet | Every 6h (:15) | 7 days | 10Gi PVC |
| MainNet | Every 6h (:00) | 7 days | 50Gi PVC |

#### Components Created
- `minio-backup-pvc` - Persistent volume for backup storage
- `minio-backup-scripts` ConfigMap - Backup script using `mc mirror`
- `minio-backup` CronJob - Scheduled backup job

#### Backup Process
1. Configures MinIO client with credentials from `minio-credentials` secret
2. Mirrors all buckets to timestamped backup directory
3. Creates metadata.json with file listing
4. Cleans up backups older than 7 days

#### Test Results
```
DevNet:  ✅ 183 B backed up (3 files)
TestNet: ✅ 54 B backed up (1 file)
MainNet: ✅ 174 B backed up (3 files)
```

#### Quota Updates
- MainNet: PVC quota increased from 10 to 15
- DevNet: PVC quota increased from 3 to 5

---

## Next Steps
1. Monitor messaging service logs for any issues
2. Add monitoring/alerting for messaging service
3. Consider off-cluster backup replication for disaster recovery
