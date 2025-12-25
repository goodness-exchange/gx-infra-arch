# CRITICAL FINDINGS - December 25, 2025

## Issue: MainNet Fabric Blockchain Network NOT DEPLOYED

### Discovery
During Q Send testing on MainNet, discovered that the `fabric-mainnet` namespace does not exist.

### Evidence

**Namespace Status:**
```
fabric            Active   57d   (legacy/shared)
fabric-devnet     Active   44d   ✅ DEPLOYED
fabric-testnet    Active   44d   ✅ DEPLOYED
fabric-mainnet    ❌ DOES NOT EXIST
```

**Deployment Manifests:**
```
/gx-coin-fabric/k8s/environments/
├── devnet/        ✅ Full deployment manifests
├── testnet/       ✅ Full deployment manifests
└── mainnet/       ❌ Only network-policies (NO fabric deployment)
```

**Documentation:**
- `03_TESTNET_DEPLOYMENT_GUIDE.md` - EXISTS
- `04_DEVNET_DEPLOYMENT_GUIDE.md` - EXISTS
- `05_MAINNET_DEPLOYMENT_GUIDE.md` - DOES NOT EXIST

### Impact

All blockchain operations on MainNet FAIL with:
```
14 UNAVAILABLE: failed to find any endorsing peers for org(s): Org1MainnetMSP, Org2MainnetMSP
```

**MainNet Features Affected:**
| Feature | Status |
|---------|--------|
| User blockchain registration (CREATE_USER) | ❌ BLOCKED |
| Q Send payments (Q_SEND_PAY) | ❌ BLOCKED |
| Token transfers (TRANSFER_TOKENS) | ❌ BLOCKED |
| Minting (MINT) | ❌ BLOCKED |
| All chaincode operations | ❌ BLOCKED |

**MainNet Features Working (DB-only):**
| Feature | Status |
|---------|--------|
| User registration (database) | ✅ Works |
| Authentication/Login | ✅ Works |
| Messaging | ✅ Works |
| File uploads | ✅ Works |

### Root Cause

The MainNet Fabric network deployment was **never completed**. Only the network policies were created on Nov 11, but no actual Fabric components (peers, orderers, CAs) were deployed.

The backend services (outbox-submitter) were configured with MainNet Fabric endpoints that don't exist:
```
FABRIC_MSP_ID=Org1MainnetMSP
FABRIC_ORG2_MSP_ID=Org2MainnetMSP
FABRIC_ORG2_PEER_ENDPOINT=peer0-org2.fabric-mainnet.svc.cluster.local:7051
```

### Tests Performed This Week

All blockchain tests that passed were on **DevNet** and **TestNet**:
- DevNet: Q Send working ✅ (Transaction: d04fc1aa...)
- TestNet: Q Send working ✅ (Transaction: 0a9e08f8...)
- MainNet: Q Send BLOCKED ❌ (No Fabric network)

### Required Actions

To enable blockchain features on MainNet:

1. **Create MainNet Fabric deployment manifests**
   - Copy from TestNet and adapt MSP IDs, namespaces, endpoints

2. **Deploy MainNet Fabric network**
   - Orderer nodes
   - Peer nodes (Org1, Org2)
   - Certificate Authorities
   - CouchDB state databases

3. **Create channel and join peers**
   - Create gxchannel-mainnet
   - Join all peers to channel

4. **Deploy chaincode**
   - Install chaincode on all peers
   - Approve and commit chaincode definition

5. **Configure wallets/identities**
   - Create admin, partner-api, super-admin identities
   - Mount wallet secrets to outbox-submitter

### User's Valid Concerns

The user correctly identified systemic issues:
1. **Not following protocols** - MainNet assumed to be ready without verification
2. **Not following promotion sequence** - Backend configured before Fabric deployed
3. **Wasting resources** - Multiple debugging sessions for infrastructure gap
4. **Lack of visibility** - No clear deployment status documentation

### Recommendations

1. **Create deployment checklist** for each environment
2. **Add health check script** that verifies all infrastructure before tests
3. **Document deployment state** in version-controlled status files
4. **Never configure backend** for an environment until Fabric is verified working

---

## Session Context for Tomorrow

### What Was Completed Today

1. ✅ Q_SEND_PAY handler implemented in outbox-submitter
2. ✅ Deployed outbox-submitter:2.2.3 to all environments
3. ✅ Fixed biometricHash (bcrypt → SHA256) across all environments
4. ✅ Fixed MainNet missing FABRIC_ORG2 env vars
5. ✅ Q Send tested successfully on DevNet
6. ✅ Q Send tested successfully on TestNet
7. ❌ Q Send BLOCKED on MainNet (no Fabric network)

### Environment Sync Analysis

Root cause of test failures when promoting code:
- **Not a code issue** - Service versions are identical
- **Data inconsistency** - Users created before v2.2.1 had bcrypt hashes
- **Missing migrations** - Code fixes didn't include data migrations

### Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/fix-user-data.js` | Fix bcrypt hashes, reset failed commands |
| `scripts/setup-test-users.js` | Create consistent test users per environment |

### Commits Pushed

1. `57a2a1a` - feat(outbox-submitter): add Q_SEND_PAY blockchain handler
2. `54d0bde` - feat(scripts): add environment sync and test user setup scripts

### Files Modified

- `/gx-protocol-backend/workers/outbox-submitter/src/index.ts`
- `/gx-protocol-backend/scripts/fix-user-data.js` (NEW)
- `/gx-protocol-backend/scripts/setup-test-users.js` (NEW)
- `/gx-infra-arch/WORK_RECORD_2025-12-25.md`

### Next Session Priority

1. **Decision needed**: Deploy MainNet Fabric or defer?
2. If deploying: Create mainnet fabric deployment guide and manifests
3. Establish deployment verification checklist
