# Environment Synchronization Report - December 26, 2025

## Summary

This document records the discrepancies found between DevNet, TestNet, and MainNet environments during a systematic comparison, and the fixes applied to achieve uniformity.

## Comparison Methodology

Following the promotion sequence: DevNet → TestNet → MainNet, we compared:
1. NetworkPolicies
2. ConfigMaps (backend-config)
3. Fabric Credentials (Secrets)
4. Volume Mounts

## Discrepancies Found and Fixed

### 1. NetworkPolicy: allow-internal-backend

**Pattern in DevNet/TestNet:**
```yaml
egress:
- ports: [7050, 7051, 7053, 7054]
  to:
  - namespaceSelector:
      kubernetes.io/metadata.name: fabric-{env}
```

**MainNet Before:**
- Only allowed egress within backend-mainnet namespace
- Fabric ports were in a separate `allow-fabric-access` policy (wrong pattern)

**Fix Applied:**
- Updated `allow-internal-backend` to include Fabric ports to `fabric-mainnet` namespace
- Deleted redundant `allow-fabric-access` policy

### 2. ConfigMap: backend-config FABRIC Variables

| Variable | DevNet | TestNet | MainNet Before | MainNet After |
|----------|--------|---------|----------------|---------------|
| FABRIC_CHAINCODE_NAME | gxtv3-devnet | gxtv3-testnet | gxtv3 ❌ | gxtv3-mainnet ✅ |
| FABRIC_CHANNEL_NAME | gxchannel-devnet | gxchannel-testnet | gxchannel ❌ | gxchannel-mainnet ✅ |
| FABRIC_MSP_ID | Org1DevnetMSP | Org1TestnetMSP | Org1MSP ❌ | Org1MainnetMSP ✅ |
| FABRIC_ORG2_MSP_ID | Org2DevnetMSP | Org2TestnetMSP | Org2MSP ❌ | Org2MainnetMSP ✅ |
| FABRIC_PEER_ENDPOINT | peer0-org1.fabric-devnet... | peer0-org1.fabric-testnet... | peer0-org1.fabric... ❌ | peer0-org1.fabric-mainnet... ✅ |
| FABRIC_ORG2_PEER_ENDPOINT | peer0-org2.fabric-devnet... | peer0-org2.fabric-testnet... | peer0-org2.fabric... ❌ | peer0-org2.fabric-mainnet... ✅ |
| FABRIC_PEER_TLS_CA_CERT_PATH | /etc/fabric/ca-cert.pem | /etc/fabric/ca-cert.pem | /fabric-wallet/tlsca-cert ❌ | /etc/fabric/ca-cert.pem ✅ |
| FABRIC_TLS_SERVER_NAME_OVERRIDE | peer0.org1.devnet.goodness.exchange | peer0.org1.testnet.goodness.exchange | peer0.org1.prod... ❌ | peer0.org1.mainnet... ✅ |
| FABRIC_ORG2_TLS_SERVER_NAME_OVERRIDE | peer0.org2.devnet.goodness.exchange | peer0.org2.testnet.goodness.exchange | peer0.org2.prod... ❌ | peer0.org2.mainnet... ✅ |

### 3. Fabric Credentials Secret

**Pattern:**
```
ca-cert.pem   - TLS CA certificate (CN=tlsca.org1.{env}.goodness.exchange)
cert.pem      - Admin identity certificate
key.pem       - Admin identity private key
```

**Verification (all correct after fix):**
- DevNet: CN=tlsca.org1.devnet.goodness.exchange ✅
- TestNet: CN=tlsca.org1.testnet.goodness.exchange ✅
- MainNet: CN=tlsca.org1.mainnet.goodness.exchange ✅

### 4. Volume Mounts

All environments now have consistent mounts:
- `/etc/fabric` - fabric-credentials secret (ca-cert.pem, cert.pem, key.pem)
- `/app/fabric-wallet` or `/fabric-wallet` - fabric-wallet secret

## Root Cause Analysis

The MainNet configuration was created as a copy from an older "prod" environment that used different naming conventions:
- Used `fabric.svc` instead of `fabric-mainnet.svc`
- Used `Org1MSP` instead of `Org1MainnetMSP`
- Used `prod.goodness.exchange` instead of `mainnet.goodness.exchange`

This happened because MainNet was configured **before** the Fabric network was deployed, using placeholder values.

## Deployment Verification Checklist

Before deploying to a new environment, verify:

1. **Namespace Exists:**
   ```bash
   kubectl get ns fabric-{env}
   kubectl get ns backend-{env}
   ```

2. **NetworkPolicies Allow Fabric:**
   ```bash
   kubectl get networkpolicy allow-internal-backend -n backend-{env} -o yaml | grep fabric-{env}
   ```

3. **ConfigMap Values Match Pattern:**
   ```bash
   kubectl get configmap backend-config -n backend-{env} -o json | jq '.data | to_entries[] | select(.key | startswith("FABRIC"))' | grep -E "{env}"
   ```

4. **TLS CA is Correct (not MSP CA):**
   ```bash
   kubectl get secret fabric-credentials -n backend-{env} -o jsonpath='{.data.ca-cert\.pem}' | base64 -d | openssl x509 -noout -subject | grep "tlsca"
   ```

5. **Fabric Connectivity Test:**
   ```bash
   kubectl exec -n backend-{env} deploy/outbox-submitter -- node -e "
   const net = require('net');
   const client = new net.Socket();
   client.setTimeout(3000);
   client.on('connect', () => { console.log('Connected'); client.destroy(); });
   client.on('error', (err) => { console.log('Error:', err.message); });
   client.connect(7051, 'peer0-org1.fabric-{env}.svc.cluster.local');
   "
   ```

6. **Fabric Clients Initialize:**
   ```bash
   kubectl logs -n backend-{env} deploy/outbox-submitter --tail=20 | grep "Successfully connected"
   ```

## Naming Conventions

| Component | Pattern | Example (MainNet) |
|-----------|---------|-------------------|
| Fabric Namespace | fabric-{env} | fabric-mainnet |
| Backend Namespace | backend-{env} | backend-mainnet |
| Channel Name | gxchannel-{env} | gxchannel-mainnet |
| Chaincode Name | gxtv3-{env} | gxtv3-mainnet |
| MSP ID Org1 | Org1{Env}MSP | Org1MainnetMSP |
| MSP ID Org2 | Org2{Env}MSP | Org2MainnetMSP |
| Peer Endpoint | peer0-org1.fabric-{env}.svc.cluster.local:7051 | peer0-org1.fabric-mainnet.svc.cluster.local:7051 |
| TLS Override | peer0.org1.{env}.goodness.exchange | peer0.org1.mainnet.goodness.exchange |

## Verification Results

After fixes, all environments show:
- ✅ Fabric clients connect successfully (4 clients per environment)
- ✅ Correct channel: gxchannel-{env}
- ✅ Correct chaincode: gxtv3-{env}
- ✅ Correct MSP IDs: Org1{Env}MSP, Org2{Env}MSP
- ✅ Correct TLS CA certificates

## Commands Executed

```bash
# Updated NetworkPolicy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal-backend
  namespace: backend-mainnet
spec:
  egress:
  - ports: [7050, 7051, 7053, 7054]
    to:
    - namespaceSelector:
        kubernetes.io/metadata.name: fabric-mainnet
  ...
EOF

# Deleted redundant policy
kubectl delete networkpolicy allow-fabric-access -n backend-mainnet

# Updated ConfigMap
kubectl patch configmap backend-config -n backend-mainnet --type='json' -p='[
  {"op": "replace", "path": "/data/FABRIC_CHAINCODE_NAME", "value": "gxtv3-mainnet"},
  {"op": "replace", "path": "/data/FABRIC_CHANNEL_NAME", "value": "gxchannel-mainnet"},
  {"op": "replace", "path": "/data/FABRIC_MSP_ID", "value": "Org1MainnetMSP"},
  ...
]'

# Restarted outbox-submitter
kubectl rollout restart deployment/outbox-submitter -n backend-mainnet
```

## Next Steps

1. Remove redundant FABRIC env vars from MainNet outbox-submitter deployment (they're now in ConfigMap)
2. Test a blockchain transaction on MainNet to verify end-to-end functionality
3. Document this checklist in a permanent location for future deployments
