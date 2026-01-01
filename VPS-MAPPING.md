# VPS MAPPING - AUTHORITATIVE REFERENCE
## Last Updated: 2026-01-01
## Status: VERIFIED AND ACTIVE

---

## CURRENT VPS INFRASTRUCTURE

| VPS | Hostname | IP Address | Role | Taint |
|-----|----------|------------|------|-------|
| VPS1 | srv1089618.hstgr.cloud | 72.60.210.201 | MainNet (Production) | none |
| VPS2 | srv1117946.hstgr.cloud | 72.61.116.210 | MainNet (Production) | none |
| VPS3 | srv1092158.hstgr.cloud | 72.61.81.3 | MainNet (Production) | none |
| VPS4 | srv1089624.hstgr.cloud | **217.196.51.190** | **DevNet/TestNet/Monitoring** | environment=nonprod:NoSchedule |

---

## Architecture Principles

### Production (MainNet) - VPS1, VPS2, VPS3
- No taints
- backend-mainnet namespace
- fabric-mainnet namespace
- High availability across 3 nodes

### Non-Production (DevNet/TestNet) - VPS4 ONLY
- Taint: `environment=nonprod:NoSchedule`
- backend-devnet namespace
- backend-testnet namespace
- fabric namespace (DevNet)
- fabric-testnet namespace
- monitoring namespace
- All development and testing workloads

---

## Kubernetes Node Labels

```yaml
# VPS1 (srv1089618)
node-id: vps1
fabric-role: mainnet-node1
backend-environment: mainnet

# VPS2 (srv1117946)
node-id: vps2
fabric-role: mainnet-node2
backend-environment: mainnet

# VPS3 (srv1092158)
node-id: vps3
fabric-role: mainnet-node3
backend-environment: mainnet

# VPS4 (srv1089624) - 217.196.51.190
node-id: vps4
environment: devnet-testnet
fabric-role: devnet-testnet
monitoring: "true"
```

---

## SSH Access

```bash
# MainNet nodes
ssh root@72.60.210.201   # VPS1
ssh root@72.61.116.210   # VPS2
ssh root@72.61.81.3      # VPS3

# DevNet/TestNet/Monitoring
ssh root@217.196.51.190  # VPS4
```

---

## Namespace to Node Mapping

| Namespace | Environment | Target Node(s) |
|-----------|-------------|----------------|
| backend-devnet | Development | VPS4 |
| backend-testnet | Staging | VPS4 |
| backend-mainnet | Production | VPS1, VPS2, VPS3 |
| fabric | DevNet Fabric | VPS4 |
| fabric-testnet | TestNet Fabric | VPS4 |
| fabric-mainnet | MainNet Fabric | VPS1, VPS2, VPS3 |
| monitoring | Observability | VPS4 |

---

## Historical Note

Prior to 2026-01-01, documentation may have contained incorrect VPS mappings due to a swap between VPS2 and VPS4. This document supersedes all previous mappings.

---

## REMEMBER

**VPS4 = srv1089624 = 217.196.51.190 = DevNet/TestNet/Monitoring**

This is the ONLY node for non-production workloads.
