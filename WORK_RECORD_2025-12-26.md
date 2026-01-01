# Work Record - December 26, 2025

## Session Summary

### 1. Environment Synchronization (Completed)

Conducted systematic comparison of DevNet, TestNet, and MainNet to identify and fix configuration discrepancies.

#### Issues Found and Fixed:

| Component | Issue | Fix Applied |
|-----------|-------|-------------|
| **NetworkPolicy** | MainNet had separate `allow-fabric-access` policy instead of integrated fabric egress in `allow-internal-backend` | Updated `allow-internal-backend` to include fabric ports to fabric-mainnet namespace; deleted redundant policy |
| **ConfigMap** | MainNet `backend-config` had old placeholder values (Org1MSP, gxchannel, fabric.svc) | Updated to correct MainNet values (Org1MainnetMSP, gxchannel-mainnet, fabric-mainnet.svc) |
| **TLS CA Path** | MainNet used `/fabric-wallet/tlsca-cert` instead of `/etc/fabric/ca-cert.pem` | Updated to match DevNet/TestNet pattern |
| **TLS Overrides** | MainNet used `prod.goodness.exchange` instead of `mainnet.goodness.exchange` | Updated to correct naming convention |

#### Verification:
- All 4 Fabric clients connect successfully to peers
- TLS CA certificates verified (CN=tlsca.org1.{env}.goodness.exchange)
- Environment documentation created: `ENVIRONMENT_SYNC_2025-12-26.md`

### 2. MainNet Blockchain Transaction Test (In Progress)

Attempted to test blockchain transactions on MainNet. Initial test was blocked by configuration issues (now fixed).

#### Current Status:

**Working:**
- Peer0-org1 can launch and connect to external chaincode
- Transactions get endorsed by Org1MainnetMSP
- Outbox-submitter processes commands

**Not Working:**
- Peer0-org2 cannot connect to external chaincode
- Error: `timeout expired while starting chaincode gxtv3-mainnet`
- Endorsement policy requires both orgs, so transactions fail

#### Root Cause:
Cross-node chaincode connectivity issue:
- Chaincode pod runs on node srv1089618
- Peer0-org2 runs on node srv1117946
- Peer's chaincode launcher times out trying to connect to chaincode across nodes
- Same topology works in DevNet (unknown why)

#### Investigation Notes:
1. DNS resolution works correctly
2. Direct TCP connectivity from test pods works
3. The Fabric peer's external chaincode launcher has specific timeout/connection behavior that differs from standard pods
4. DevNet uses short service name (`gxtv3-devnet:7052`) vs MainNet FQDN (`gxtv3-chaincode.fabric-mainnet.svc.cluster.local:7052`)

### 3. Additional Troubleshooting (Session 2 - ~06:00 UTC)

#### Issues Identified and Fixes Attempted:

| Issue | Attempted Fix | Result |
|-------|---------------|--------|
| **peer0-org2 node affinity** | Was set to `mainnet-node4` (non-existent), changed to `mainnet-node2` | ✅ Fixed - peer now schedules correctly |
| **StatefulSet corruption** | Had ccaas-run ConfigMap mount causing issues, restored to original config | ✅ Fixed - peers start properly |
| **Chaincode builder type** | build-info.json had `ccaas` but ccaas_builder lacks run script | Changed to `external` builder which has proper run script |
| **Chaincode launch timeout** | Peers still timing out trying to launch chaincode | ❌ Still failing |

#### Technical Findings:

1. **Builder Scripts Comparison:**
   - `ccaas_builder` (in 2.5.11): Has detect, build, release - NO run script
   - `external_builder`: Has detect, build, release, AND run script
   - The run script outputs connection.json and keeps process alive

2. **Image Version Difference:**
   - DevNet: `fabric-peer:2.5` (v2.5.14)
   - MainNet: `fabric-peer:2.5.11`
   - Both versions have same builder structure

3. **Current Chaincode Package State:**
   - metadata.json: `{"type":"ccaas","label":"gxtv3-mainnet"}`
   - connection.json: `{"address":"gxtv3-chaincode.fabric-mainnet.svc.cluster.local:7052","dial_timeout":"10s","tls_required":false}`
   - build-info.json: `{"builder_name":"external"}` (changed from ccaas)

4. **Network Connectivity Verified:**
   - Test pod from node2 (srv1117946) can connect to chaincode service: `10.43.221.1:7052 open`
   - Issue is specific to Fabric peer's chaincode launcher mechanism

#### Current State (as of ~06:20 UTC):

**StatefulSets:**
- peer0-org1: Running on srv1089618, affinity: mainnet-node1 ✅
- peer0-org2: Running on srv1117946, affinity: mainnet-node2 ✅

**Build Configuration:**
- Both peers have `builder_name: external` in build-info.json
- Peers restart with this configuration persisted on PVC

**OutboxCommands:**
- 2 CREATE_USER commands in PENDING state (attempts=0)
- Waiting for endorsement from both orgs

**Outstanding Issue:**
Transaction submission still failing with endorsement timeout. Root cause appears to be in how the Fabric peer's chaincode launcher handles cross-node external chaincode connections.

### 4. Pending Items (Deferred to Future Session)

- [ ] Investigate why DevNet works with same topology
- [ ] Consider deploying chaincode on all nodes with pod anti-affinity
- [ ] Consider updating MainNet peer image to 2.5 (same as DevNet)
- [ ] Complete blockchain transaction test on MainNet

### Commands Reference

```bash
# Fixed NetworkPolicy
kubectl patch networkpolicy allow-internal-backend -n backend-mainnet ...

# Updated ConfigMap
kubectl patch configmap backend-config -n backend-mainnet --type='json' -p='[
  {"op": "replace", "path": "/data/FABRIC_CHAINCODE_NAME", "value": "gxtv3-mainnet"},
  {"op": "replace", "path": "/data/FABRIC_CHANNEL_NAME", "value": "gxchannel-mainnet"},
  ...
]'

# Test blockchain transaction (user registration)
curl -X POST http://localhost:3061/api/v1/auth/register -H "Content-Type: application/json" -d '...'

# Check command status
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c \
  "SELECT commandType, status, fabricTxId FROM OutboxCommand ORDER BY createdAt DESC LIMIT 5;"
```

### Session Files
- `/home/sugxcoin/prod-blockchain/gx-infra-arch/ENVIRONMENT_SYNC_2025-12-26.md` - Environment sync documentation
- `/tmp/mainnet_blockchain_test.sh` - Test script for MainNet transactions
