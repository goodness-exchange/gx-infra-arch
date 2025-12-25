# MainNet Messaging Infrastructure

This directory contains Kubernetes manifests for the GX Protocol messaging system on MainNet.

## Components

### 1. MinIO (S3-compatible storage)
- **File:** `minio.yaml`
- **Purpose:** File storage for voice messages and file attachments
- **Storage:** 50GB PVC
- **Bucket:** `gx-voice-messages`

### 2. Ingress Configuration
- **File:** `ingress.yaml`
- **Routes:**
  - `/socket.io` - WebSocket endpoint for real-time messaging
  - `/api/v1/conversations` - Conversation management
  - `/api/v1/messages` - Message send/receive
  - `/api/v1/files` - File upload/download
  - `/api/v1/voice` - Voice message handling
  - `/api/v1/keys` - Encryption key management
  - `/api/v1/groups` - Group chat management

### 3. Network Policy
- **File:** `network-policy.yaml`
- **Purpose:** Allow ingress traffic to API services
- **Ports:** 3000-3008

### 4. Database Schema
- **File:** `database-schema.sql`
- **Tables:**
  - `Conversation` - Chat containers
  - `ConversationParticipant` - User membership
  - `Message` - Encrypted messages
  - `MessageDeliveryReceipt` - Delivery tracking
  - `UserSignalKey` - E2E encryption keys
  - `SignalPreKey` - One-time pre-keys
  - `GroupEncryptionKey` - Group chat keys
  - `GroupParticipantKey` - Per-participant wrapped keys

## Deployment Order

1. Create MinIO secret:
   ```bash
   kubectl create secret generic minio-credentials \
     --from-literal=root-user=gxmainnet \
     --from-literal=root-password=<secure-password> \
     -n backend-mainnet
   ```

2. Deploy MinIO:
   ```bash
   kubectl apply -f minio.yaml
   ```

3. Create bucket:
   ```bash
   kubectl exec -n backend-mainnet minio-0 -- mc alias set local http://localhost:9000 gxmainnet <password>
   kubectl exec -n backend-mainnet minio-0 -- mc mb local/gx-voice-messages
   ```

4. Apply network policy:
   ```bash
   kubectl apply -f network-policy.yaml
   ```

5. Apply ingress:
   ```bash
   kubectl apply -f ingress.yaml
   ```

6. Run database migrations:
   ```bash
   kubectl cp database-schema.sql backend-mainnet/postgres-0:/tmp/
   kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -f /tmp/database-schema.sql
   ```

## Environment Variables for svc-messaging

```yaml
env:
- name: S3_ENDPOINT
  value: "http://minio.backend-mainnet.svc.cluster.local:9000"
- name: S3_BUCKET_VOICE
  value: "gx-voice-messages"
- name: S3_REGION
  value: "us-east-1"
- name: S3_FORCE_PATH_STYLE
  value: "true"
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: minio-credentials
      key: root-user
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: minio-credentials
      key: root-password
```

## Verification

```bash
# Check MinIO
kubectl exec -n backend-mainnet minio-0 -- mc ls local/

# Check messaging tables
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c "\dt"

# Test endpoints
curl -s https://api.gxcoin.money/socket.io/?EIO=4&transport=polling
curl -s https://api.gxcoin.money/health
```

## URLs

- **API:** https://api.gxcoin.money
- **WebSocket:** wss://api.gxcoin.money/socket.io
- **Wallet Frontend:** https://wallet.gxcoin.money
