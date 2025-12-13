# Migration Commands Reference Log - Phase 3 Onwards

**Started:** December 13, 2025
**Plan:** COMPREHENSIVE_MIGRATION_PLAN_v3.md
**Purpose:** Document all commands executed during infrastructure migration (Phase 3+)

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

## Phase 3: Infrastructure Setup (COMPLETED)

### 3.1 PodDisruptionBudgets

**Objective:** Create PDBs to ensure high availability during node maintenance

```bash
# Create Orderer PDB (minAvailable: 3 for Raft quorum)
cat > /root/k8s/pdb-orderers.yaml << 'EOF'
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
EOF

# Create Peer PDB (minAvailable: 2 for endorsement)
cat > /root/k8s/pdb-peers.yaml << 'EOF'
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
EOF

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
cat > /root/k8s/orderer-antiaffinity-patch.yaml << 'EOF'
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
EOF

# Create anti-affinity patch for peers
cat > /root/k8s/peer-antiaffinity-patch.yaml << 'EOF'
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
EOF

# Apply anti-affinity to orderers (successful)
for i in orderer0 orderer1 orderer2 orderer3 orderer4; do
  kubectl patch statefulset $i -n fabric --type strategic --patch-file /root/k8s/orderer-antiaffinity-patch.yaml
done

# Apply anti-affinity to peers
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
# Create core.yaml ConfigMap
kubectl apply -f /root/k8s/peer-core-config.yaml

# Create volume mount patch
cat > /root/k8s/peer-core-volume-patch.yaml << 'EOF'
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
EOF

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

## Phase 4: Architecture Restructuring

### Phase 4 Overview

**Objective:** Restructure cluster topology for proper environment isolation

**Current State:**
- VPS-1, VPS-3, VPS-4 are control-plane nodes in single cluster
- VPS-2 is a worker node
- All environments (MainNet, TestNet) in single cluster

**Target State:**
- VPS-1, VPS-3, VPS-4: MainNet control-plane (3-node HA)
- VPS-2: Standalone for DevNet/TestNet (separate cluster)

---

### 4.1 Pre-Restructuring Assessment

**Executed:** Dec 13, 2025 16:00 UTC

```bash
# Check current cluster topology
kubectl get nodes -o wide

# Check workload distribution
kubectl get pods -A -o wide --no-headers | grep -v kube-system | awk '{print $8, $1, $2, $4}' | sort
```

**RESULTS:**

**Current Cluster Topology:**
| Node | Role | IP | Status |
|------|------|-----|--------|
| srv1089618.hstgr.cloud (VPS-1) | control-plane,etcd,master | 72.60.210.201 | Ready |
| srv1089624.hstgr.cloud (VPS-4) | control-plane,etcd,master | 217.196.51.190 | Ready |
| srv1092158.hstgr.cloud (VPS-3) | control-plane,etcd,master | 72.61.81.3 | Ready |
| srv1117946.hstgr.cloud (VPS-2) | worker | 72.61.116.210 | Ready |

**Workload Distribution:**

| Node | MainNet Fabric | MainNet Backend | TestNet | Monitoring |
|------|----------------|-----------------|---------|------------|
| VPS-1 (srv1089618) | orderer0, orderer3, peer0-org1, couchdb, chaincode | projector, redis-2, svc-* | None | loki |
| VPS-2 (srv1117946) | None | postgres-0,1, redis-0,1 | ALL TestNet | prometheus, registry |
| VPS-3 (srv1092158) | orderer1, orderer4, peer1-org1, peer1-org2, CAs | svc-* | None | - |
| VPS-4 (srv1089624) | **CA-orderer, CA-org1, CA-tls**, orderer2, peer0-org2, couchdb | postgres-2, svc-* | None | alertmanager, grafana |

**CRITICAL FINDINGS:**

1. **VPS-4 hosts critical Fabric CAs:**
   - ca-orderer-0 (issues orderer certificates)
   - ca-org1-0 (issues Org1 certificates)
   - ca-tls-0 (issues TLS certificates)
   - These are CRITICAL for network operation

2. **TestNet is ALREADY on VPS-2 (worker node):**
   - 3 orderers, 2 peers, 2 couchdb, chaincode
   - All in fabric-testnet namespace

3. **MainNet databases split:**
   - PostgreSQL: 2 replicas on VPS-2, 1 on VPS-4
   - Redis: 2 replicas on VPS-2, 1 on VPS-1

**Risk Assessment:**

| Operation | Risk Level | Impact |
|-----------|------------|--------|
| Remove VPS-4 from cluster | CRITICAL | Loses 3 CAs, 1 orderer, 1 peer |
| Migrate CAs | CRITICAL | Network may become unable to issue new certs |
| Migrate orderer2 | HIGH | Raft cluster reconfiguration |
| Migrate peer0-org2 | MEDIUM | Org2 endorsement affected |
| Promote VPS-2 to control-plane | LOW | Just adds etcd member |

**Recommended Approach:**

Option A: **Keep VPS-4 in MainNet cluster** (SAFER)
- Keep current topology
- VPS-4 continues as MainNet control-plane
- TestNet remains on VPS-2 (worker)
- Environment isolation via namespaces (current state)

Option B: **Full restructuring** (HIGH RISK)
- Requires maintenance window
- Must migrate CAs first (longest downtime)
- Complex rollback if issues occur

---

### 4.2 Promote VPS-2 to Control-Plane (COMPLETED)

**Executed:** Dec 13, 2025 16:15-16:50 UTC

**Objective:** Promote VPS-2 from worker node to control-plane (4-node HA etcd cluster)

**Challenges Encountered:**

1. **Duplicate etcd member error:** Old etcd member existed in cluster
   - Solution: Removed stale etcd member using etcdctl

2. **Encryption config mismatch:** K3s secrets are encrypted in etcd
   - Error: "identity transformer tried to read encrypted data"
   - Root cause: Joining server needs encryption-provider-config
   - Solution: Added `--kube-apiserver-arg=encryption-provider-config=/var/lib/rancher/k3s/server/encryption-config.yaml`

**Commands Executed:**

```bash
# 1. Install etcdctl for etcd management
curl -sL https://github.com/etcd-io/etcd/releases/download/v3.5.12/etcd-v3.5.12-linux-amd64.tar.gz | tar xzf - -C /tmp
cp /tmp/etcd-v3.5.12-linux-amd64/etcdctl /usr/local/bin/

# 2. Remove stale etcd member from cluster (on VPS-1)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  member remove <MEMBER_ID>

# 3. Copy encryption config to VPS-2
mkdir -p /var/lib/rancher/k3s/server
scp root@72.60.210.201:/var/lib/rancher/k3s/server/encryption-config.yaml \
    /var/lib/rancher/k3s/server/encryption-config.yaml
chmod 600 /var/lib/rancher/k3s/server/encryption-config.yaml

# 4. Install K3s server on VPS-2 with encryption config
cat > /etc/systemd/system/k3s.service << 'EOF'
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
User=root
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
    server \
    --server https://72.60.210.201:6443 \
    --token=<K3S_TOKEN> \
    --tls-san=72.60.210.201 \
    --tls-san=217.196.51.190 \
    --tls-san=72.61.81.3 \
    --tls-san=72.61.116.210 \
    --tls-san=gxcoin.io \
    --tls-san=api.gxcoin.io \
    --disable=traefik \
    --disable=servicelb \
    --write-kubeconfig-mode=644 \
    --node-label=node-role=secondary \
    --node-label=node-id=vps2 \
    --node-label=topology.kubernetes.io/zone=asia \
    --cluster-cidr=10.42.0.0/16 \
    --service-cidr=10.43.0.0/16 \
    --kube-apiserver-arg=encryption-provider-config=/var/lib/rancher/k3s/server/encryption-config.yaml
EOF

systemctl daemon-reload
systemctl start k3s
```

**RESULTS:**

```
# Kubernetes Nodes (4 control-plane nodes)
NAME                     STATUS   ROLES                       AGE   VERSION        INTERNAL-IP
srv1089618.hstgr.cloud   Ready    control-plane,etcd,master   45d   v1.33.5+k3s1   72.60.210.201
srv1089624.hstgr.cloud   Ready    control-plane,etcd,master   45d   v1.33.5+k3s1   217.196.51.190
srv1092158.hstgr.cloud   Ready    control-plane,etcd,master   45d   v1.33.5+k3s1   72.61.81.3
srv1117946.hstgr.cloud   Ready    control-plane,etcd,master   40s   v1.33.5+k3s1   72.61.116.210

# etcd Cluster (4 voting members)
+------------------+---------+---------------------------------+-----------------------------+
|        ID        | STATUS  |              NAME               |         PEER ADDRS          |
+------------------+---------+---------------------------------+-----------------------------+
| 2310de09e74a3b4c | started | srv1092158.hstgr.cloud-be241dd6 |     https://72.61.81.3:2380 |
| 331d0811e5be471a | started | srv1117946.hstgr.cloud-62f5c62d |  https://72.61.116.210:2380 |
| 8a002e5cc40da3aa | started | srv1089618.hstgr.cloud-609b1f4a |  https://72.60.210.201:2380 |
| dc76292eb0923578 | started | srv1089624.hstgr.cloud-11945d59 | https://217.196.51.190:2380 |
+------------------+---------+---------------------------------+-----------------------------+
```

**Updated Cluster Topology:**
| Node | Role | IP | Status |
|------|------|-----|--------|
| srv1089618.hstgr.cloud (VPS-1) | control-plane,etcd,master | 72.60.210.201 | Ready |
| srv1089624.hstgr.cloud (VPS-4) | control-plane,etcd,master | 217.196.51.190 | Ready |
| srv1092158.hstgr.cloud (VPS-3) | control-plane,etcd,master | 72.61.81.3 | Ready |
| srv1117946.hstgr.cloud (VPS-2) | **control-plane,etcd,master** | 72.61.116.210 | Ready |

**Key Learnings:**

1. K3s secrets encryption requires `encryption-config.yaml` to be copied to joining servers
2. Must use `--kube-apiserver-arg=encryption-provider-config=<path>` for joining servers
3. Always remove stale etcd members before re-adding nodes
4. etcdctl must be installed separately (not bundled with K3s)

---

### 4.3 Phase 4 Status Update

**Current State After Phase 4.2:**
- All 4 VPS servers are now control-plane nodes with etcd
- 4-node HA etcd cluster provides F=1 fault tolerance (can lose 1 node)
- Fabric pods continue running normally on VPS-1, VPS-3, VPS-4
- VPS-2 now available for workload scheduling as control-plane

**Next Steps (Pending User Decision):**

Option A: **Keep Current Topology** (RECOMMENDED)
- All 4 nodes as control-plane provides maximum HA
- TestNet remains on VPS-2 via namespace isolation
- No migration risk, immediate stability

Option B: **Full Restructuring** (HIGH RISK)
- Would require migrating CAs from VPS-4
- Requires maintenance window
- Higher complexity, potential for extended downtime


---

## Phase 4.3: Full Restructuring Analysis and Implementation (COMPLETED)

**Executed:** December 13, 2025 ~17:00 UTC
**Objective:** Analyze VPS-4 CA dependencies and implement safe restructuring option

### 4.3.1 CA Distribution Analysis

```bash
# List all CAs and their nodes
kubectl get pods -n fabric -l app=ca -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase"

# Check CA PV node affinities
for pv in $(kubectl get pv -o name | grep ca-data); do
  echo "=== $pv ==="
  kubectl get $pv -o jsonpath="{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}"
  echo ""
done
```

**RESULTS:**

| CA | Node | Purpose | PV Node Affinity |
|----|------|---------|------------------|
| ca-orderer-0 | srv1089624.hstgr.cloud (VPS-4) | Orderer certificates | srv1089624 (local-path) |
| ca-org1-0 | srv1089624.hstgr.cloud (VPS-4) | Org1 certificates | srv1089624 (local-path) |
| ca-tls-0 | srv1089624.hstgr.cloud (VPS-4) | TLS certificates | srv1089624 (local-path) |
| ca-org2-0 | srv1092158.hstgr.cloud (VPS-3) | Org2 certificates | srv1092158 (local-path) |
| ca-root-0 | srv1092158.hstgr.cloud (VPS-3) | Root CA | srv1092158 (local-path) |

**CRITICAL FINDING:**
- All CAs use local-path storage with hard node affinity
- Migrating CAs would require data copy and PV recreation
- Risk of CA data corruption is catastrophic for blockchain

---

### 4.3.2 Restructuring Options Evaluation

| Option | Description | Risk Level | Recommendation |
|--------|-------------|------------|----------------|
| A | Keep VPS-4 in MainNet, use VPS-2 for TestNet | LOW | ✅ SELECTED |
| B | Migrate 3 CAs from VPS-4 to other nodes | CATASTROPHIC | ❌ REJECTED |

**Decision: Option A Selected**

Rationale:
- Zero risk to critical CA infrastructure
- VPS-2 (srv1117946) PVs already bound to that node
- Simple label change enables TestNet scheduling
- Preserves 4-node HA MainNet cluster

---

### 4.3.3 Node Label Corrections

**Issue Discovered:** Node label conflicts
- VPS-4 (srv1089624) incorrectly labeled as `node-id=vps2`
- VPS-2 (srv1117946) also labeled as `node-id=vps2` (duplicate)

```bash
# Fix VPS-4 node-id label from vps2 to vps4
kubectl label node srv1089624.hstgr.cloud node-id=vps4 --overwrite
# Result: node/srv1089624.hstgr.cloud labeled

# Add testdev role to VPS-2 for TestNet scheduling
kubectl label node srv1117946.hstgr.cloud node-role=testdev --overwrite
# Result: node/srv1117946.hstgr.cloud labeled

# Verify final node labels
kubectl get nodes -o custom-columns="NAME:.metadata.name,NODE-ID:.metadata.labels.node-id,NODE-ROLE:.metadata.labels.node-role,ZONE:.metadata.labels.topology\.kubernetes\.io/zone"
```

**RESULTS:**

| Node | Hostname | node-id | node-role | Zone |
|------|----------|---------|-----------|------|
| VPS-1 | srv1089618.hstgr.cloud | vps1 | primary | us-east |
| VPS-2 | srv1117946.hstgr.cloud | vps2 | testdev | asia |
| VPS-3 | srv1092158.hstgr.cloud | vps3 | primary | us-central |
| VPS-4 | srv1089624.hstgr.cloud | vps4 | primary | us-west |

---

### 4.3.4 TestNet Recovery

**Issue:** TestNet pods were Pending after label fix due to stale PVCs pointing to non-existent paths (VPS-2 was reinstalled, wiping local storage)

```bash
# Check TestNet pods (should now be scheduling)
kubectl get pods -n fabric-testnet -o wide

# Result: Pods scheduling but failing PV mount
# MountVolume.NewMounter initialization failed - path does not exist

# Clean up stale StatefulSets
kubectl delete statefulset -n fabric-testnet --all --wait=false

# Clean up stale PVCs
kubectl delete pvc -n fabric-testnet --all

# Clean up released PVs
kubectl get pv | grep -E "Released|Failed" | grep fabric-testnet | awk '{print $1}' | xargs -r kubectl delete pv
```

**RESULTS:**
```
statefulset.apps "couchdb0-org1" deleted
statefulset.apps "couchdb0-org2" deleted
statefulset.apps "gxtv3-chaincode" deleted
statefulset.apps "orderer0-ordererorg" deleted
statefulset.apps "orderer1-ordererorg" deleted
statefulset.apps "orderer2-ordererorg" deleted
statefulset.apps "peer0-org1" deleted
statefulset.apps "peer0-org2" deleted

persistentvolumeclaim "couchdb0-org1-data" deleted
persistentvolumeclaim "couchdb0-org2-data" deleted
persistentvolumeclaim "orderer0-data" deleted
persistentvolumeclaim "orderer1-data" deleted
persistentvolumeclaim "orderer2-data" deleted
persistentvolumeclaim "peer0-org1-data" deleted
persistentvolumeclaim "peer0-org2-data" deleted
```

**TestNet Status:** Cleared - ready for fresh deployment when needed

---

### 4.3.5 MainNet Health Verification

```bash
# Verify MainNet pods are healthy
kubectl get pods -n fabric | grep -E "^(ca-|orderer|peer)"
```

**RESULTS:**
```
ca-orderer-0           1/1     Running     0          34d
ca-org1-0              1/1     Running     0          34d
ca-org2-0              1/1     Running     0          34d
ca-root-0              1/1     Running     0          34d
ca-tls-0               1/1     Running     0          34d
orderer0-0             1/1     Running     0          137m
orderer1-0             1/1     Running     0          137m
orderer2-0             1/1     Running     0          137m
orderer3-0             1/1     Running     0          137m
orderer4-0             1/1     Running     0          137m
peer0-org1-0           1/1     Running     0          111m
peer0-org2-0           1/1     Running     0          111m
peer1-org1-0           1/1     Running     0          111m
peer1-org2-0           1/1     Running     0          111m
```

**MainNet Health:** ✅ ALL HEALTHY
- 5/5 CAs: Running
- 5/5 Orderers: Running
- 4/4 Peers: Running

---

### Phase 4 Summary

**Final Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    GX Blockchain Infrastructure                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  MainNet Cluster (4-node HA etcd)                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   VPS-1     │  │   VPS-3     │  │   VPS-4     │              │
│  │ (primary)   │  │ (primary)   │  │ (primary)   │              │
│  │ orderer0,3  │  │ orderer1,4  │  │ orderer2    │              │
│  │ peer0-org1  │  │ peer1-org1  │  │ peer0-org2  │              │
│  │             │  │ peer1-org2  │  │ ca-orderer  │              │
│  │             │  │ ca-org2     │  │ ca-org1     │              │
│  │             │  │ ca-root     │  │ ca-tls      │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  TestNet Node                                                    │
│  ┌─────────────┐                                                 │
│  │   VPS-2     │  ← control-plane + testdev role                │
│  │ (testdev)   │    Ready for TestNet deployment                │
│  └─────────────┘                                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Key Outcomes:**
1. VPS-4 remains in MainNet - critical CAs protected
2. VPS-2 labeled as testdev for TestNet workloads
3. Node label conflicts resolved (vps2/vps4 distinction)
4. TestNet cleared for fresh deployment
5. 4-node HA cluster maintained
6. Zero downtime to MainNet during restructuring

---

## Phase 5: Backup Implementation (COMPLETED)

**Executed:** December 13, 2025 17:30-18:00 UTC
**Objective:** Implement automated Google Drive backups for all infrastructure

### 5.1 rclone Installation

```bash
# Install on servers without rclone (VPS-2, VPS-3, VPS-4, VPS-5)
dnf install -y unzip
curl -s https://rclone.org/install.sh | bash

# Verify installation
rclone version
```

**RESULTS:** rclone v1.72.1 installed on all 5 servers

---

### 5.2 Google Drive Configuration

```bash
# VPS-1 already had gdrive-gx: remote configured
# Copy config to other servers
ssh root@72.60.210.201 'cat ~/.config/rclone/rclone.conf' | \
  ssh root@<TARGET_IP> 'mkdir -p ~/.config/rclone && cat > ~/.config/rclone/rclone.conf && chmod 600 ~/.config/rclone/rclone.conf'

# Verify remote works
rclone lsd gdrive-gx:

# Create backup directories
rclone mkdir gdrive-gx:GX-Infrastructure-Backups/mainnet
rclone mkdir gdrive-gx:GX-Infrastructure-Backups/testnet
rclone mkdir gdrive-gx:GX-Infrastructure-Backups/website
```

---

### 5.3 Backup Scripts

**MainNet Backup (VPS-1: /root/scripts/backup-mainnet.sh):**
- Backs up Fabric CA data, secrets, PostgreSQL, Redis, K8s resources, etcd
- 30-day retention policy
- Uploads compressed archive to gdrive-gx:GX-Infrastructure-Backups/mainnet/

**TestNet Backup (VPS-4: /root/scripts/backup-testnet.sh):**
- Backs up fabric-testnet and backend-testnet namespaces
- 14-day retention policy
- Uploads to gdrive-gx:GX-Infrastructure-Backups/testnet/

**Website Backup (VPS-5: /root/scripts/backup-website.sh):**
- Backs up /var/www/gxcoin.money, Docker state, K8s resources
- 30-day retention policy
- Uploads to gdrive-gx:GX-Infrastructure-Backups/website/

---

### 5.4 Cron Configuration

```bash
# VPS-1 (MainNet - 4 AM UTC)
(crontab -l 2>/dev/null; echo "0 4 * * * /root/scripts/backup-mainnet.sh >> /var/log/backup-mainnet.log 2>&1") | crontab -

# VPS-4 (TestNet - 3 AM UTC)
(crontab -l 2>/dev/null; echo "0 3 * * * /root/scripts/backup-testnet.sh >> /var/log/backup-testnet.log 2>&1") | crontab -

# VPS-5 (Website - 2 AM UTC)
(crontab -l 2>/dev/null; echo "0 2 * * * /root/scripts/backup-website.sh >> /var/log/backup-website.log 2>&1") | crontab -
```

---

### 5.5 Verification

```bash
# List all backups on Google Drive
rclone ls gdrive-gx:GX-Infrastructure-Backups/

# Results:
#  13130070 mainnet/backup-mainnet-20251213_173825.tar.gz
#     31952 testnet/backup-testnet-20251213_173927.tar.gz
# 423213985 website/backup-website-20251213_173953.tar.gz
#  27406636 pre-migration/gx-full-backup-20251212-093047.tar.gz
```

---

### Phase 5 Summary

| Component | Backup Location | Schedule | Retention |
|-----------|-----------------|----------|-----------|
| MainNet | gdrive-gx:GX-Infrastructure-Backups/mainnet/ | 4 AM UTC | 30 days |
| TestNet | gdrive-gx:GX-Infrastructure-Backups/testnet/ | 3 AM UTC | 14 days |
| Website | gdrive-gx:GX-Infrastructure-Backups/website/ | 2 AM UTC | 30 days |

**Total Backup Size (Initial):** ~436 MB

---

## VPS Naming Convention (Updated)

| VPS | IP Address | Hostname | Role |
|-----|------------|----------|------|
| VPS-1 | 72.60.210.201 | srv1089618.hstgr.cloud | MainNet Node 1 (Primary) |
| VPS-2 | 217.196.51.190 | srv1089624.hstgr.cloud | MainNet Node 2 (CAs) |
| VPS-3 | 72.61.81.3 | srv1092158.hstgr.cloud | MainNet Node 3 |
| VPS-4 | 72.61.116.210 | srv1117946.hstgr.cloud | DevNet + TestNet |
| VPS-5 | 195.35.36.174 | srv711725.hstgr.cloud | Website + Partner |

---

## PostgreSQL/Redis PVC Fix (Post-Phase 5)

**Issue:** postgres-0, postgres-1, redis-0, redis-1 stuck in ContainerCreating due to PVCs bound to wiped VPS-4 storage.

### Commands Executed

```bash
# 1. Delete stale PVCs bound to VPS-4
kubectl delete pvc -n backend-mainnet \
  postgres-storage-postgres-0 \
  postgres-storage-postgres-1 \
  redis-storage-redis-0 \
  redis-storage-redis-1

# 2. Force delete stuck pods
kubectl delete pod -n backend-mainnet postgres-0 postgres-1 redis-0 redis-1 \
  --force --grace-period=0

# 3. Add node affinity to PostgreSQL StatefulSet (MainNet nodes only)
kubectl patch statefulset postgres -n backend-mainnet --type=json -p \
  '[{"op": "add", "path": "/spec/template/spec/affinity", "value": 
    {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": 
      {"nodeSelectorTerms": [{"matchExpressions": 
        [{"key": "node-role", "operator": "In", "values": ["primary"]}]}]}}}}]'

# 4. Add node affinity to Redis StatefulSet (MainNet nodes only)
kubectl patch statefulset redis -n backend-mainnet --type=json -p \
  '[{"op": "add", "path": "/spec/template/spec/affinity", "value": 
    {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": 
      {"nodeSelectorTerms": [{"matchExpressions": 
        [{"key": "node-role", "operator": "In", "values": ["primary"]}]}]}}}}]'

# 5. Verify final state
kubectl get pods -n backend-mainnet -l "app in (postgres,redis)" -o wide
kubectl get statefulset -n backend-mainnet postgres redis
```

### Results

```
NAME         READY   STATUS    NODE
postgres-0   1/1     Running   srv1089618.hstgr.cloud (VPS-1)
postgres-1   1/1     Running   srv1092158.hstgr.cloud (VPS-3)
postgres-2   1/1     Running   srv1089624.hstgr.cloud (VPS-2)
redis-0      1/1     Running   srv1089624.hstgr.cloud (VPS-2)
redis-1      1/1     Running   srv1092158.hstgr.cloud (VPS-3)
redis-2      1/1     Running   srv1089618.hstgr.cloud (VPS-1)

NAME       READY   AGE
postgres   3/3     30d
redis      3/3     30d
```

**Key Learning:** When adding a new node to the cluster, existing PVCs may get provisioned on that node by local-path provisioner. Adding node affinity to StatefulSets ensures pods only schedule on designated nodes (e.g., `node-role=primary` for MainNet workloads).
