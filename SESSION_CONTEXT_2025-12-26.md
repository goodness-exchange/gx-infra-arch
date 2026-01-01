# Session Context - December 26, 2025

## Session End Time: ~03:20 UTC

## What Was Accomplished

### 1. Environment Synchronization (COMPLETED)
Systematic comparison and alignment of DevNet, TestNet, and MainNet configurations:

- **NetworkPolicies**: Fixed MainNet `allow-internal-backend` to include fabric ports to `fabric-mainnet` namespace
- **ConfigMap**: Updated `backend-config` with correct MainNet values:
  - FABRIC_CHAINCODE_NAME: gxtv3-mainnet
  - FABRIC_CHANNEL_NAME: gxchannel-mainnet
  - FABRIC_MSP_ID: Org1MainnetMSP
  - FABRIC_PEER_ENDPOINT: peer0-org1.fabric-mainnet.svc.cluster.local:7051
  - FABRIC_PEER_TLS_CA_CERT_PATH: /etc/fabric/ca-cert.pem
- **TLS Certificates**: Verified all environments use correct TLS CA (CN=tlsca.org1.{env}.goodness.exchange)

### 2. MainNet Blockchain Transaction Test (IN PROGRESS - BLOCKED)

Attempted blockchain transaction test, encountered cross-node chaincode connectivity issue.

**Current State:**
- User registered: `mainnet_test_1766718021@gxcoin.money` (profileId: d92a001e-fe70-4183-a9c5-0f196186f44a)
- OutboxCommands: 2 CREATE_USER commands in FAILED/LOCKED state
- Error: peer0-org2 cannot connect to chaincode across nodes

## Current Issue

### Cross-Node Chaincode Connectivity Problem

**Topology:**
```
Node srv1089618:
  - gxtv3-chaincode-0 (10.42.0.201)
  - peer0-org1-0 (10.42.0.200) ✅ Works

Node srv1117946:
  - peer0-org2-0 (10.42.3.131) ❌ Cannot connect to chaincode
```

**Error in peer0-org2 logs:**
```
could not launch chaincode gxtv3-mainnet:b2f4348f51bbbe5443f85f0610d3a0b035035bc7c28c1c7d8d1c5e0f1dda03cd:
chaincode registration failed: timeout expired while starting chaincode
```

**Observations:**
1. Direct TCP connectivity from test pods works (cross-node networking is fine)
2. DNS resolution works correctly
3. DevNet has same topology but works (chaincode on srv1089618, peer0-org2 on srv1117946)
4. Difference: DevNet connection.json uses short service name (`gxtv3-devnet:7052`), MainNet uses FQDN

## Files Created/Modified

| File | Purpose |
|------|---------|
| `/home/sugxcoin/prod-blockchain/gx-infra-arch/ENVIRONMENT_SYNC_2025-12-26.md` | Environment sync documentation and checklist |
| `/home/sugxcoin/prod-blockchain/gx-infra-arch/WORK_RECORD_2025-12-26.md` | Work record for today |
| `/tmp/mainnet_blockchain_test.sh` | Test script for MainNet transactions |

## Resume Instructions

When resuming, the priority should be:

1. **Fix cross-node chaincode connectivity** - Options:
   - Compare DevNet vs MainNet chaincode package (connection.json)
   - Update MainNet chaincode with short service name
   - Or deploy chaincode on multiple nodes with pod anti-affinity

2. **Reset and retry CREATE_USER commands:**
   ```bash
   kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c \
     "UPDATE \"OutboxCommand\" SET status = 'PENDING', attempts = 0, error = NULL WHERE status = 'FAILED';"
   kubectl rollout restart deployment/outbox-submitter -n backend-mainnet
   ```

3. **Verify transaction commits:**
   ```bash
   kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c \
     "SELECT \"commandType\", status, \"fabricTxId\" FROM \"OutboxCommand\" ORDER BY \"createdAt\" DESC LIMIT 5;"
   ```

## Key Commands Reference

```bash
# Check Fabric client connections
kubectl logs -n backend-mainnet deploy/outbox-submitter --tail=30 | grep -E "connected|Fabric"

# Check peer logs for chaincode issues
kubectl logs -n fabric-mainnet peer0-org2-0 --tail=50 | grep -E "chaincode|error|launch"

# Check chaincode pod
kubectl get pods -n fabric-mainnet -o wide | grep chaincode
kubectl logs -n fabric-mainnet gxtv3-chaincode-0

# Test cross-node connectivity
kubectl run test-conn --rm -it --restart=Never --image=busybox -n fabric-mainnet -- \
  nc -zv gxtv3-chaincode.fabric-mainnet.svc.cluster.local 7052
```

## Namespaces Reference

| Environment | Backend Namespace | Fabric Namespace |
|-------------|-------------------|------------------|
| DevNet | backend-devnet | fabric (legacy) / fabric-devnet |
| TestNet | backend-testnet | fabric-testnet |
| MainNet | backend-mainnet | fabric-mainnet |

## Port Forwards (may need restart)

```bash
# MainNet Identity Service
kubectl port-forward svc/svc-identity -n backend-mainnet 3061:3001 &
```
