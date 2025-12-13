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

