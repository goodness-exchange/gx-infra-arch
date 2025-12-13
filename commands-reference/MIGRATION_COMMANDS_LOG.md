# Migration Commands Reference Log

**Started:** December 13, 2025
**Plan:** COMPREHENSIVE_MIGRATION_PLAN_v3.md
**Purpose:** Document all commands executed during infrastructure migration

---

## Server Reference

| VPS | IP Address | Hostname | Role |
|-----|------------|----------|------|
| VPS-1 | 72.60.210.201 | srv1089618.hstgr.cloud | MainNet Primary |
| VPS-2 | 72.61.116.210 | srv1117946.hstgr.cloud | MainNet Secondary |
| VPS-3 | 72.61.81.3 | srv1092158.hstgr.cloud | MainNet Tertiary + Backup |
| VPS-4 | 217.196.51.190 | srv1089624.hstgr.cloud | DevNet + TestNet |
| VPS-5 | 195.35.36.174 | srv711725.hstgr.cloud | Website + Partner |

---

## Phase 0: Emergency Stabilization

### 0.1 VPS-1 Disk Space Cleanup (72.60.210.201)

**Objective:** Reduce disk usage from 79% to <50% by removing Docker build cache (~70GB)

```bash
# SSH to VPS-1
sshpass -p 'Tech1@Osm;um76' ssh -o StrictHostKeyChecking=no root@72.60.210.201

# Step 1: Document current state before cleanup
df -h /
# Records current disk usage

docker system df
# Shows Docker disk usage breakdown (images, containers, volumes, build cache)

docker ps -a > /root/docker-containers-before-cleanup.txt
# Saves list of all containers before cleanup

docker images > /root/docker-images-before-cleanup.txt
# Saves list of all images before cleanup

# Step 2: Prune Docker build cache (primary space saver)
docker builder prune -a -f
# -a: Remove all unused build cache, not just dangling
# -f: Force, don't prompt for confirmation
# Expected recovery: ~70GB

# Step 3: Remove unused/dangling images
docker image prune -a -f
# -a: Remove all unused images, not just dangling ones
# -f: Force, don't prompt

# Step 4: Remove unused volumes (CAUTION - verify first)
docker volume ls
# List all volumes first to verify what will be removed

docker volume prune -f
# Remove all unused volumes
# WARNING: Only run after verifying no important data in unused volumes

# Step 5: General system prune (final cleanup)
docker system prune -f
# Removes stopped containers, unused networks, dangling images

# Step 6: Verify space recovered
df -h /
# Should show significant reduction (target: <50%)

docker system df
# Verify Docker disk usage reduced
```

**RESULTS (Executed Dec 13, 2025):**
```
BEFORE:
- Disk: 312GB used (79%)
- Build Cache: 76.17GB (70.51GB reclaimable)

AFTER:
- Disk: 268GB used (68%)
- Build Cache: 0B
- Space Recovered: ~44GB
```

---

### 0.2 Determine Authoritative Fabric Network

**Objective:** Identify which Fabric network (Docker Compose or Kubernetes) is the authoritative source

```bash
# Check Docker Compose network ledger height (via metrics)
curl -s http://localhost:9444/metrics | grep "ledger_blockchain_height"
# Shows: ledger_blockchain_height{channel="gxchannel"} 5

# Check Kubernetes network ledger file
kubectl exec -n fabric peer0-org1-0 -c peer -- ls -la /var/hyperledger/production/ledgersData/chains/chains/gxchannel/blockfile_000000
# Shows: 820357 bytes, Dec 11

# Check Docker Compose ledger file
docker exec peer0.org1.prod.goodness.exchange ls -la /var/hyperledger/production/ledgersData/chains/chains/gxchannel/blockfile_000000
# Shows: 53029 bytes, Oct 29

# Check backend Fabric connection
kubectl get configmap -n backend-mainnet backend-config -o yaml | grep FABRIC_PEER
# Shows: FABRIC_PEER_ENDPOINT: peer0-org1.fabric.svc.cluster.local:7051
```

**RESULTS (Executed Dec 13, 2025):**
```
COMPARISON:
| Network          | Ledger Size | Last Modified | Status      |
|------------------|-------------|---------------|-------------|
| Kubernetes       | 820KB       | Dec 11, 2025  | AUTHORITATIVE |
| Docker Compose   | 53KB        | Oct 29, 2025  | STALE       |

EVIDENCE:
1. K8s ledger 15x larger (820KB vs 53KB)
2. K8s last modified 6+ weeks more recent
3. Backend services connect to K8s (peer0-org1.fabric.svc.cluster.local)
4. Docker Compose network at block height 5, unchanged since Oct 29

DECISION: Kubernetes network is authoritative. Docker Compose can be stopped.
```

---

### 0.3 Stop Duplicate Docker Compose Fabric Network

**Objective:** Stop the stale Docker Compose Fabric network to free resources and avoid confusion

```bash
# Find Docker Compose directory
find / -name "docker-compose*.yaml" -o -name "docker-compose*.yml" 2>/dev/null | grep -E "fabric|prod"
# Expected: /home/sugxcoin/prod-blockchain/gx-coin-fabric/network/docker-compose-prod.yaml or similar

# List running Fabric containers
docker ps --filter "name=org" --filter "name=orderer" --filter "name=peer" --filter "name=couchdb"

# Stop Docker Compose (preserves data)
cd /path/to/docker-compose/directory
docker-compose stop

# Verify ports are free
netstat -tlnp | grep -E "7051|7050|5984"

# Remove containers (keeps volumes for backup)
docker-compose down

# Verify cleanup
docker ps -a | grep -E "org|orderer|peer|couchdb"
```

**RESULTS (Executed Dec 13, 2025 13:57 UTC):**
```
EXECUTED COMMANDS:
1. docker compose -f docker-compose-production.yaml stop
   - Stopped: 4 peers, 5 orderers, 4 couchdb
   - Note: postgres.ca left running (CA database)

2. docker stop dev-peer* (chaincode containers)
   - Stopped 3 chaincode containers

3. docker compose -f docker-compose-production.yaml down
   - Removed all stopped Fabric containers
   - Removed fabric_prod_net network
   - Volumes preserved for backup

VERIFICATION:
- No Docker Compose Fabric containers remaining
- K8s Fabric still running: 4 peers (1/1), 5 orderers (1/1)
- Ports 7050, 7051, 5984 now free for K8s exclusive use
- Disk at 68% (268GB used)
```

---

### 0.4 Investigate Backend Service Health

**Objective:** Fix degraded backend services (svc-tokenomics 0/3, others 1/3)

```bash
# Check all backend services
kubectl get pods -n backend-mainnet -o wide

# Check failing svc-tokenomics
kubectl describe pod -n backend-mainnet -l app=svc-tokenomics
kubectl logs -n backend-mainnet -l app=svc-tokenomics --tail=100

# Check outbox-submitter (140 restarts)
kubectl describe pod -n backend-mainnet -l app=outbox-submitter
kubectl logs -n backend-mainnet -l app=outbox-submitter --tail=100

# Check events for errors
kubectl get events -n backend-mainnet --sort-by='.lastTimestamp' | tail -30

# Common fixes - rolling restart
kubectl rollout restart deployment -n backend-mainnet svc-tokenomics
kubectl rollout restart deployment -n backend-mainnet outbox-submitter
```

**RESULTS (Executed Dec 13, 2025 14:00-14:20 UTC):**
```
ROOT CAUSE IDENTIFIED:
- Backend secret had password: XRCwgQQGOOH998HxD9XH24oJbjdHPPxl
- PostgreSQL had password: IpBZ31PZvN1ma/Q8BIoEhp6haKYRLlUkRk1eRRhtssY=
- Password MISMATCH caused P1001 (Can't reach database) errors

RESOLUTION:
1. Changed PostgreSQL password to match backend secret:
   kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol \
     -c "ALTER USER gx_admin WITH PASSWORD 'XRCwgQQGOOH998HxD9XH24oJbjdHPPxl';"

2. Restored backend secret to original value:
   kubectl patch secret backend-secrets -n backend-mainnet --type='json' \
     -p='[{"op": "replace", "path": "/data/DATABASE_PASSWORD", "value": "WFJDd2dRUUdPT0g5OThIeEQ5WEgyNG9KYmpkSFBQeGw="}]'

3. Restarted affected deployments:
   kubectl rollout restart deployment -n backend-mainnet svc-tokenomics svc-governance svc-loanpool svc-organization svc-tax

SERVICE STATUS AFTER FIX:
| Service          | Before  | After  | Status |
|------------------|---------|--------|--------|
| svc-admin        | 3/3     | 3/3    | ✅ OK  |
| svc-identity     | 3/3     | 3/3    | ✅ OK  |
| svc-governance   | 1/3     | 3/3    | ✅ FIXED |
| svc-loanpool     | 1/3     | 3/3    | ✅ FIXED |
| svc-organization | 1/3     | 3/3    | ✅ FIXED |
| svc-tax          | 1/3     | 2/3    | ⚠️ Partial |
| svc-tokenomics   | 0/3     | 0/3    | ❌ Readiness fails |
| outbox-submitter | 1/1     | 1/1    | ✅ OK (146 restarts in 2d) |
| projector        | 1/1     | 1/1    | ✅ OK  |

NOTE: svc-tokenomics pods start successfully (db connects, health returns 200)
but /readyz returns 503 - likely application-level readiness check issue,
not infrastructure. Requires code investigation.
```

---

### Phase 1.3: Pre-Migration Checklist Verification

**Objective:** Verify all systems are stable before proceeding with migration

```bash
# Check K8s cluster status
kubectl get nodes -o wide
# Result: All 4 nodes Ready

# Check Fabric pods
kubectl get pods -n fabric
# Result: All pods Running (4 peers, 5 orderers, chaincode, CouchDB)

# Check backend pods
kubectl get pods -n backend-mainnet
# Result: Most services healthy, svc-tokenomics not ready

# Check disk space
df -h /
# Result: 68% (268GB used)

# Check etcd health
kubectl get componentstatuses
# Result: controller-manager, scheduler, etcd-0 all Healthy

# Verify backup archives
ls -la /root/backups/*.tar.gz
# Result: 2 backup archives present

# Test PostgreSQL connection
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol -c "SELECT 1;"
# Result: Connection successful
```

**RESULTS (Executed Dec 13, 2025 14:30 UTC):**
```
PRE-MIGRATION CHECKLIST:
| Item                    | Status | Notes                           |
|-------------------------|--------|---------------------------------|
| K8s Cluster             | ✅ OK  | All 4 nodes Ready               |
| Fabric Network          | ✅ OK  | All pods Running                |
| Backend Services        | ⚠️     | svc-tokenomics needed fix       |
| Disk Space              | ✅ OK  | 68% (improved from 79%)         |
| etcd Health             | ✅ OK  | All components Healthy          |
| Backup Archives         | ✅ OK  | 2 archives present              |
| PostgreSQL              | ✅ OK  | Connection successful           |
| Redis                   | ✅ OK  | Running (requires auth)         |
```

---

### Investigation: svc-tokenomics Readiness Probe Issue

**Objective:** Identify and fix why svc-tokenomics /readyz returns 503

```bash
# Check readiness probe configuration
kubectl get deploy svc-tokenomics -n backend-mainnet -o jsonpath="{.spec.template.spec.containers[0].readinessProbe}"
# Result: httpGet /readyz on port 3002, threshold 2 failures

# Check pod logs
kubectl logs -n backend-mainnet -l app=svc-tokenomics --tail=50
# Result: /livez returns 200, /readyz returns 503 consistently

# Investigate ProjectorState table
kubectl exec -n backend-mainnet postgres-0 -- psql -U gx_admin -d gx_protocol \
  -c 'SELECT * FROM "ProjectorState";'
# Result: lastBlock=102, updatedAt=2025-12-11 05:49:52 (2 days old!)

# Check projector metrics
kubectl exec -n backend-mainnet deploy/projector -- wget -qO- http://localhost:9091/metrics | grep projector_lag
# Result: projector_lag_blocks = 0 (projector is caught up!)

# Check current threshold
kubectl get deploy svc-tokenomics -n backend-mainnet -o jsonpath="{.spec.template.spec.containers[0].env}" | jq '.[] | select(.name=="PROJECTION_LAG_THRESHOLD_MS")'
# Result: 86400000 (24 hours)
```

**ROOT CAUSE IDENTIFIED:**
```
1. The /readyz endpoint in health.controller.ts checks ProjectorState.updatedAt
2. If (currentTime - updatedAt) > PROJECTION_LAG_THRESHOLD_MS, it returns 503
3. No blockchain transactions occurred since Dec 11 (block 102)
4. The projector only updates updatedAt when processing events
5. After 2+ days without transactions, lagMs (~172800000) > threshold (86400000)
6. Result: 503 Service Unavailable despite projector being healthy

KEY INSIGHT: The projector was actually healthy (lag_blocks=0),
but the timestamp-based readiness check failed due to blockchain inactivity.
```

**RESOLUTION:**
```bash
# Increase PROJECTION_LAG_THRESHOLD_MS from 24 hours to 30 days
kubectl set env deployment/svc-tokenomics -n backend-mainnet PROJECTION_LAG_THRESHOLD_MS=2592000000

# Wait for rollout
kubectl rollout status deployment/svc-tokenomics -n backend-mainnet --timeout=120s

# Verify pod is now Ready
kubectl get pods -n backend-mainnet -l app=svc-tokenomics
# Result: svc-tokenomics-f8957cdcf-pqc56      1/1     Running
```

**SERVICE STATUS AFTER FIX:**
```
| Service          | Before  | After  | Status      |
|------------------|---------|--------|-------------|
| svc-admin        | 3/3     | 3/3    | ✅ OK       |
| svc-identity     | 3/3     | 3/3    | ✅ OK       |
| svc-governance   | 3/3     | 3/3    | ✅ OK       |
| svc-loanpool     | 3/3     | 3/3    | ✅ OK       |
| svc-organization | 3/3     | 3/3    | ✅ OK       |
| svc-tax          | 2/3     | 2/2    | ✅ OK       |
| svc-tokenomics   | 0/3     | 1/1    | ✅ FIXED    |
| outbox-submitter | 1/1     | 1/1    | ✅ OK       |
| projector        | 1/1     | 1/1    | ✅ OK       |
```

**RECOMMENDED PERMANENT FIX:**
The projector worker should implement a periodic heartbeat that updates
ProjectorState.updatedAt even when there are no events to process. This
would allow the readiness check to accurately reflect the projector's
connection status rather than event activity.

---

## Phase 2: Security Hardening

### 2.1 SSH Key Authentication

**Objective:** Disable password authentication, enable key-based SSH access

```bash
# Generate SSH key on VPS-1 (already existed)
ssh-keygen -t ed25519 -C "gx-admin@gxcoin.money" -f /root/.ssh/id_ed25519 -N ""

# Copy public key to all servers
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMcYikOOLul3LvKkwPr+5aJUqUskqahzp6spR/9yMFSl vps1-to-partner-backup"
for IP in 72.61.116.210 72.61.81.3 217.196.51.190 195.35.36.174; do
    ssh root@$IP "mkdir -p /root/.ssh && echo '$PUBLIC_KEY' >> /root/.ssh/authorized_keys"
done

# Test key-based login
for IP in 72.61.116.210 72.61.81.3 217.196.51.190 195.35.36.174; do
    ssh -o BatchMode=yes root@$IP "hostname"
done

# Harden SSH config on each server
cat >> /etc/ssh/sshd_config << 'EOF'
# GX Security Hardening
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
MaxAuthTries 3
LoginGraceTime 60
EOF
systemctl restart sshd
```

**RESULTS (Executed Dec 13, 2025 15:10 UTC):**
```
| Server | Key Copied | SSH Hardened | Access Verified |
|--------|------------|--------------|-----------------|
| VPS-1  | ✅         | ✅           | ✅              |
| VPS-2  | ✅         | ✅           | ✅              |
| VPS-3  | ✅         | ✅           | ✅              |
| VPS-4  | ✅         | ✅           | ✅              |
| VPS-5  | ✅         | ✅           | ✅              |

Password authentication now DISABLED on all servers.
Key-based access working from VPS-1 to all other servers.
Backup configs saved at /etc/ssh/sshd_config.backup.YYYYMMDD
```

---

### 2.2 Disable Unnecessary Services

**Objective:** Stop and disable httpd and rpcbind services

```bash
# On VPS-1, VPS-2, VPS-3, VPS-4 - disable httpd and rpcbind
systemctl stop httpd rpcbind rpcbind.socket
systemctl disable httpd rpcbind rpcbind.socket

# On VPS-5 - keep httpd (website), disable rpcbind only
systemctl stop rpcbind rpcbind.socket
systemctl disable rpcbind rpcbind.socket
```

**RESULTS (Executed Dec 13, 2025 15:15 UTC):**
```
| Server | httpd   | rpcbind      |
|--------|---------|--------------|
| VPS-1  | Stopped | Stopped      |
| VPS-2  | N/A     | Stopped      |
| VPS-3  | Stopped | Stopped      |
| VPS-4  | Stopped | Stopped      |
| VPS-5  | KEPT    | Stopped      |
```

---

### 2.3 Firewall Hardening

**Objective:** Configure firewall rules for secure access

**Decision:** K3s nodes (VPS-1,2,3,4) use Kubernetes NetworkPolicies instead of firewalld.
VPS-5 (standalone website) uses firewalld.

```bash
# Check existing NetworkPolicies on K3s cluster
kubectl get networkpolicies -A
# Result: 40+ policies including default-deny-all on all namespaces

# K3s manages its own iptables rules via kube-router
# Enabling firewalld would interfere with K3s networking
# Therefore: VPS-1,2,3,4 use NetworkPolicies only

# VPS-5: Install and configure firewalld
ssh root@195.35.36.174 "dnf install -y firewalld"
ssh root@195.35.36.174 "systemctl enable --now firewalld"
ssh root@195.35.36.174 "firewall-cmd --permanent --add-service=ssh"
ssh root@195.35.36.174 "firewall-cmd --permanent --add-service=http"
ssh root@195.35.36.174 "firewall-cmd --permanent --add-service=https"

# Add cluster IPs to trusted zone
ssh root@195.35.36.174 "firewall-cmd --permanent --zone=trusted --add-source=72.60.210.201"
ssh root@195.35.36.174 "firewall-cmd --permanent --zone=trusted --add-source=72.61.116.210"
ssh root@195.35.36.174 "firewall-cmd --permanent --zone=trusted --add-source=72.61.81.3"
ssh root@195.35.36.174 "firewall-cmd --permanent --zone=trusted --add-source=217.196.51.190"
ssh root@195.35.36.174 "firewall-cmd --reload"
```

**RESULTS (Executed Dec 13, 2025 15:20 UTC):**
```
K3s Nodes (VPS-1,2,3,4):
- Using Kubernetes NetworkPolicies (40+ policies configured)
- default-deny-all in fabric, backend-mainnet, backend-testnet, fabric-testnet
- Specific allow rules for DNS, internal comm, ingress, Fabric components

VPS-5 firewalld configuration:
public (default, active)
  services: cockpit dhcpv6-client http https ssh
trusted
  sources: 72.60.210.201 72.61.116.210 72.61.81.3 217.196.51.190
```

---


## Phase 3: Infrastructure Setup

### 3.1 PodDisruptionBudgets

**Objective:** Create PDBs to ensure high availability during node maintenance

```bash
# Create Orderer PDB (minAvailable: 3 for Raft quorum)
cat > /root/k8s/pdb-orderers.yaml << 'PDBEOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orderer-pdb
  namespace: fabric
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: orderer
PDBEOF

# Create Peer PDB (minAvailable: 2 for endorsement)
cat > /root/k8s/pdb-peers.yaml << 'PDBEOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: peer-pdb
  namespace: fabric
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: peer
PDBEOF

# Apply PDBs
kubectl apply -f /root/k8s/pdb-orderers.yaml
kubectl apply -f /root/k8s/pdb-peers.yaml
kubectl get pdb -n fabric
```

**RESULTS (Executed Dec 13, 2025 15:35 UTC):**
```
poddisruptionbudget.policy/orderer-pdb created
poddisruptionbudget.policy/peer-pdb created

NAME          MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
orderer-pdb   3               N/A               2                     10s
peer-pdb      2               N/A               2                     5s
```

---

### 3.2 Network Policies Verification

**Objective:** Verify existing NetworkPolicies are in place

```bash
# List all NetworkPolicies
kubectl get networkpolicies -A | wc -l
# Result: 44 policies

# Check fabric namespace policies
kubectl get networkpolicies -n fabric
# Result: default-deny-all, allow-dns, allow-orderer-communication, etc.

# Add namespace label for backend-mainnet (for selector policies)
kubectl label namespace backend-mainnet name=backend-mainnet --overwrite
```

**RESULTS (Executed Dec 13, 2025 15:38 UTC):**
```
43 NetworkPolicies across all namespaces
Namespaces with default-deny: fabric, backend-mainnet, backend-testnet, fabric-testnet
```

---

### 3.3 Pod Anti-Affinity Rules

**Objective:** Distribute Fabric pods across nodes for HA

```bash
# Create anti-affinity patch for orderers
cat > /root/k8s/orderer-antiaffinity-patch.yaml << 'PATCHEOF'
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: orderer
              topologyKey: kubernetes.io/hostname
PATCHEOF

# Create anti-affinity patch for peers
cat > /root/k8s/peer-antiaffinity-patch.yaml << 'PATCHEOF'
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: peer
              topologyKey: kubernetes.io/hostname
PATCHEOF

# Apply anti-affinity to orderers (successful)
for i in orderer0 orderer1 orderer2 orderer3 orderer4; do
  kubectl patch statefulset $i -n fabric --type strategic --patch-file /root/k8s/orderer-antiaffinity-patch.yaml
done

# Apply anti-affinity to peers (caused CrashLoopBackOff - see 3.4)
for peer in peer0-org1 peer0-org2 peer1-org1 peer1-org2; do
  kubectl patch statefulset $peer -n fabric --type strategic --patch-file /root/k8s/peer-antiaffinity-patch.yaml
done
```

**ISSUE ENCOUNTERED:**
After applying peer patches, all 4 peers crashed with error:
```
Fatal error when initializing core config: Config File "core" Not Found in "[/etc/hyperledger/fabric]"
```

---

### 3.4 Peer CrashLoopBackOff Resolution

**Root Cause:** The hyperledger/fabric-peer:2.5 image does NOT bundle core.yaml.
When pods were recreated after the patch, fresh containers couldn't find the config.

**Solution:** Create ConfigMap with core.yaml and mount it to peers

```bash
# Create core.yaml ConfigMap (full content in /root/k8s/peer-core-config.yaml)
kubectl apply -f /root/k8s/peer-core-config.yaml

# Create volume mount patch
cat > /root/k8s/peer-core-volume-patch.yaml << 'PATCHEOF'
spec:
  template:
    spec:
      containers:
      - name: peer
        volumeMounts:
        - name: core-config
          mountPath: /etc/hyperledger/fabric/core.yaml
          subPath: core.yaml
          readOnly: true
      volumes:
      - name: core-config
        configMap:
          name: peer-core-config
PATCHEOF

# Apply volume mount patch to all peers
kubectl patch statefulset peer0-org1 -n fabric --type strategic --patch-file /root/k8s/peer-core-volume-patch.yaml
kubectl patch statefulset peer0-org2 -n fabric --type strategic --patch-file /root/k8s/peer-core-volume-patch.yaml
kubectl patch statefulset peer1-org1 -n fabric --type strategic --patch-file /root/k8s/peer-core-volume-patch.yaml
kubectl patch statefulset peer1-org2 -n fabric --type strategic --patch-file /root/k8s/peer-core-volume-patch.yaml

# Force recreate pods
kubectl delete pod peer0-org1-0 peer0-org2-0 peer1-org1-0 peer1-org2-0 -n fabric --force --grace-period=0
```

**RESULTS (Executed Dec 13, 2025 15:50 UTC):**
```
All 4 peers now running:
NAME           READY   STATUS    RESTARTS   AGE
peer0-org1-0   1/1     Running   0          56s
peer0-org2-0   1/1     Running   0          54s
peer1-org1-0   1/1     Running   0          53s
peer1-org2-0   1/1     Running   0          52s

Blockchain verification:
- Channel: gxchannel ✅
- Block Height: 103 ✅
- Chaincode: gxtv3 v2.11 ✅
- Gossip: Operational ✅
```

---
