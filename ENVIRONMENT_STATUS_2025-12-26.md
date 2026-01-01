# Environment Status - December 26, 2025

## Overall Status Summary

| Environment | Backend Services | Fabric Peers | Blockchain Transactions | User Auth |
|-------------|------------------|--------------|------------------------|-----------|
| **DevNet** | Working | Working | Working | Working |
| **TestNet** | Working | Working | Working | Working |
| **MainNet** | Working | Running (issues) | **BLOCKED** | Working |

---

## DevNet Status

**Namespace:** `backend-devnet` | `fabric` (legacy) / `fabric-devnet`

### Backend Services
All services deployed and operational.

### Fabric Network
- Peers: `peer0-org1-0`, `peer0-org2-0` - Running
- Orderer: Running
- Chaincode: `gxtv3-devnet` - Running and responding

### Blockchain Transactions
- CREATE_USER: Working
- TRANSFER_TOKENS (Q-Send): Working
- KYC Updates: Working

---

## TestNet Status

**Namespace:** `backend-testnet` | `fabric-testnet`

### Backend Services
All services deployed and operational.

### Fabric Network
- Peers: `peer0-org1-0`, `peer0-org2-0` - Running
- Orderer: Running
- Chaincode: `gxtv3-testnet` - Running and responding

### Blockchain Transactions
- CREATE_USER: Working
- TRANSFER_TOKENS (Q-Send): Working

---

## MainNet Status

**Namespace:** `backend-mainnet` | `fabric-mainnet`

### Backend Services
All services deployed and operational:
- svc-identity
- svc-tokenomics
- svc-admin
- svc-messaging
- outbox-submitter
- All supporting services

### Fabric Network

**Working:**
- Peers: `peer0-org1-0`, `peer0-org2-0` - Both pods running
- Orderer: `orderer0-ordererorg-0` - Running
- Chaincode: `gxtv3-chaincode-0` - Running and listening
- Gossip: Peers communicating with each other
- Channel: `gxchannel-mainnet` - Joined by both peers

**NOT Working:**
- Cross-node chaincode invocation
- Transaction endorsement (requires both orgs)

### Blockchain Transactions

**Status: BLOCKED**

Root cause: When peer0-org2 (on node srv1117946) tries to invoke the chaincode (on node srv1089618), it times out.

Error: `timeout expired while starting chaincode gxtv3-mainnet`

### User Authentication

Working - users can register/login, profile data stored in database. Blockchain sync is blocked.

---

## Technical Details

### Chaincode Deployment Topology

```
Node srv1089618 (mainnet-node1):
  - gxtv3-chaincode-0 (10.42.0.211:7052)
  - peer0-org1-0 (10.42.0.215)
  - orderer0-ordererorg-0

Node srv1117946 (mainnet-node2):
  - peer0-org2-0 (10.42.3.151)

Node srv1092158 (mainnet-node3):
  - Database components
```

### Known Issues for MainNet

1. **Chaincode Launch Timeout**
   - Peer0-org2 cannot launch external chaincode across nodes
   - Same topology works in DevNet (unknown why)
   - TCP connectivity works, issue is in Fabric peer's chaincode launcher

2. **Builder Configuration**
   - Changed from `ccaas` to `external` builder
   - External builder has run script, ccaas does not
   - Still experiencing timeouts

### Recommended Next Steps for MainNet

1. Deploy chaincode on all nodes with anti-affinity (so each peer has local access)
2. OR investigate DevNet's working configuration more closely
3. OR upgrade peer image from 2.5.11 to 2.5 (same as DevNet)

---

## Services Deployment Matrix

| Service | DevNet | TestNet | MainNet |
|---------|--------|---------|---------|
| svc-identity | ✅ | ✅ | ✅ |
| svc-tokenomics | ✅ | ✅ | ✅ |
| svc-admin | ✅ | ✅ | ✅ |
| svc-messaging | ✅ | ✅ | ✅ |
| outbox-submitter | ✅ | ✅ | ✅ |
| gx-wallet-frontend | ✅ | ✅ | ✅ |
| svc-governance | ❓ | ❓ | ✅ |
| svc-loanpool | ❓ | ❓ | ✅ |
| svc-organization | ❓ | ❓ | ✅ |
| svc-tax | ❓ | ❓ | ✅ |

---

*Last Updated: December 26, 2025 ~06:25 UTC*
