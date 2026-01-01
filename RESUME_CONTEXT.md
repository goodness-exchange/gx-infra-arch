# Resume Context - Last Updated: December 26, 2025 ~03:20 UTC

## Quick Status

| Environment | Backend | Fabric | Blockchain Transactions |
|-------------|---------|--------|------------------------|
| DevNet | ✅ Working | ✅ Working | ✅ Working |
| TestNet | ✅ Working | ✅ Working | ✅ Working |
| MainNet | ✅ Working | ⚠️ Partial | ❌ Blocked |

## Current Priority: MainNet Blockchain

### What Was Done Today (Dec 26)

1. **Environment Synchronization** (COMPLETED)
   - Fixed NetworkPolicy `allow-internal-backend` to include fabric ports to `fabric-mainnet`
   - Updated ConfigMap `backend-config` with correct MainNet values
   - Verified TLS certificates across all environments
   - Created documentation: `ENVIRONMENT_SYNC_2025-12-26.md`

2. **MainNet Blockchain Transaction Test** (BLOCKED)
   - Test user registered: `mainnet_test_1766718021@gxcoin.money`
   - CREATE_USER commands fail due to cross-node chaincode issue

### Current Issue

**Problem:** Peer0-org2 cannot connect to external chaincode

**Topology:**
```
Node srv1089618:
  - gxtv3-chaincode-0 ✅
  - peer0-org1-0 ✅ (works - same node as chaincode)

Node srv1117946:
  - peer0-org2-0 ❌ (fails - different node from chaincode)
```

**Error:**
```
timeout expired while starting chaincode gxtv3-mainnet
```

**Observation:** DevNet has identical topology but works. Difference may be:
- DevNet uses short service name: `gxtv3-devnet:7052`
- MainNet uses FQDN: `gxtv3-chaincode.fabric-mainnet.svc.cluster.local:7052`

### Next Steps

1. Compare DevNet vs MainNet chaincode package connection.json
2. Update MainNet chaincode package with short service name OR
3. Scale chaincode to run on multiple nodes

## Key Files Created Today

| File | Purpose |
|------|---------|
| `SESSION_CONTEXT_2025-12-26.md` | Detailed session context |
| `WORK_RECORD_2025-12-26.md` | Work log |
| `ENVIRONMENT_SYNC_2025-12-26.md` | Environment sync documentation |

## Critical Commands

```bash
# Check MainNet blockchain status
kubectl logs -n backend-mainnet deploy/outbox-submitter --tail=30
kubectl logs -n fabric-mainnet peer0-org2-0 --tail=30 | grep chaincode

# Reset failed commands
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c \
  "UPDATE \"OutboxCommand\" SET status='PENDING', attempts=0 WHERE status='FAILED';"

# Check command status
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c \
  "SELECT \"commandType\", status, \"fabricTxId\" FROM \"OutboxCommand\" ORDER BY \"createdAt\" DESC LIMIT 5;"
```

## Namespaces Reference

| Environment | Backend Namespace | Fabric Namespace |
|-------------|-------------------|------------------|
| DevNet | backend-devnet | fabric / fabric-devnet |
| TestNet | backend-testnet | fabric-testnet |
| MainNet | backend-mainnet | fabric-mainnet |

---

## Previous Session Context (Dec 25)

### Environment Sync Tasks (from earlier)

Some tasks may still be pending:
- Deploy missing services (governance, loanpool, organization, tax) to DevNet/TestNet
- svc-identity version audit
- Version tag strategy implementation

### Key URLs

| Environment | Frontend | API |
|-------------|----------|-----|
| MainNet | https://wallet.gxcoin.money | https://api.gxcoin.money |
| TestNet | https://testnet.gxcoin.money | https://testnet.gxcoin.money |
| DevNet | https://devnet.gxcoin.money | https://devnet.gxcoin.money |
