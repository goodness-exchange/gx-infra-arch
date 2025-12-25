# Resume Context - December 25, 2025

## Session Summary
Deployed and configured messaging infrastructure across all environments (DevNet, TestNet, MainNet).
Fixed mainnet network routing to allow ports 80/443 on VPS1-3.

## Current State

### Messaging Service Status
| Environment | Pods | Health | Prometheus |
|-------------|------|--------|------------|
| DevNet | 1/1 Running | ✅ Healthy | ✅ Scraped |
| TestNet | 1/1 Running | ✅ Healthy | ✅ Scraped |
| MainNet | 2/2 Running | ✅ Healthy | ✅ Scraped |

### Infrastructure Components Deployed
1. **MinIO S3 Storage** - All environments
2. **Messaging Database Schema** - All environments
3. **Ingress with WebSocket support** - All environments
4. **NetworkPolicies** - Updated for messaging ports
5. **Secrets** - `minio-credentials` in all environments
6. **Backups** - CronJobs running every 6 hours
7. **Monitoring** - 16 Prometheus alert rules active

### Key URLs
- MainNet: https://wallet.gxcoin.money, https://api.gxcoin.money
- TestNet: https://testnet.gxcoin.money
- DevNet: https://devnet.gxcoin.money

### Recent Commits (gx-infra-arch)
```
59d08de feat(monitoring): add messaging service Prometheus alerts
d167303 feat(backup): add MinIO backup CronJob for all environments
81d20fa feat(secrets): add MinIO credentials as Kubernetes secrets
9ec1f41 fix(testnet): correct redis-secret redis-url to point to testnet
c62d335 docs: add Redis configuration verification for all environments
```

### Files Created/Modified Today
- `k8s/mainnet/messaging/minio.yaml`
- `k8s/mainnet/messaging/ingress.yaml`
- `k8s/mainnet/messaging/network-policy.yaml`
- `k8s/mainnet/messaging/database-schema.sql`
- `k8s/mainnet/messaging/minio-credentials-secret.yaml`
- `k8s/mainnet/messaging/minio-backup.yaml`
- `k8s/mainnet/messaging/monitoring-alerts.yaml`
- `k8s/mainnet/messaging/svc-messaging-env.yaml`
- `k8s/mainnet/messaging/README.md`
- `WORK_RECORD_2025-12-25.md`

### Completed Tasks
1. ✅ Deploy messaging to MainNet
2. ✅ Update frontend with messaging UI
3. ✅ Fix Redis authentication issue
4. ✅ Fix testnet redis-secret URL
5. ✅ Set up MinIO credentials as secrets
6. ✅ Configure MinIO backups
7. ✅ Add Prometheus monitoring and alerts
8. ✅ Fix mainnet network routing (iptables DNAT for ports 80/443)
9. ✅ Add Cloudflare DNS A records (wallet.gxcoin.money, api.gxcoin.money)
10. ✅ Fix NEXTAUTH_SECRET missing on mainnet frontend
11. ✅ Fix login "Invalid Credentials" error (internal K8s routing for NextAuth)

### MainNet Network Routing
Configured iptables DNAT rules on all mainnet nodes to route ports 80/443 to ingress controller:

| Node | IP | Status |
|------|-----|--------|
| VPS1 | 72.60.210.201 | ✅ Configured |
| VPS2 | 72.61.116.210 | ✅ Configured |
| VPS3 | 72.61.81.3 | ✅ Configured |

Ingress controller pod IP: 10.42.2.204 (runs on VPS3)

### Cloudflare DNS Configuration (Completed)
| Domain | IP | Environment |
|--------|-----|-------------|
| wallet.gxcoin.money | 72.61.81.3 | MainNet |
| api.gxcoin.money | 72.60.210.201, 72.61.116.210, 72.61.81.3 | MainNet |
| devnet.gxcoin.money | 217.196.51.190 | DevNet |
| testnet.gxcoin.money | 217.196.51.190 | TestNet |

### Remaining Next Steps
1. Monitor messaging service logs for any issues
2. Configure Grafana dashboard for messaging metrics
3. Consider off-cluster backup replication for disaster recovery
4. Consider script to auto-update DNAT rules if ingress pod IP changes

### Test Credentials (for browser testing)
| Environment | Email | Password |
|-------------|-------|----------|
| MainNet | mainnet_msg_1766642581@gxcoin.test | TestPass123 |
| MainNet | mainnet_msg2_1766642581@gxcoin.test | TestPass123 |

### Important Notes
- Redis passwords are different per environment (verified and fixed)
- MainNet uses `redis-credentials` secret, others use `redis-secret`
- Prometheus requires `environment` toleration to run on vps4
- NetworkPolicies updated to allow port 3007 for metrics scraping

## Quick Health Check Commands
```bash
# Check all messaging pods
kubectl get pods -l app=svc-messaging -A

# Check messaging health
for ns in backend-devnet backend-testnet backend-mainnet; do
  echo "$ns:" && kubectl exec -n $ns deploy/svc-messaging -- wget -qO- http://127.0.0.1:3007/health
done

# Check MinIO pods
kubectl get pods -l app=minio -A

# Check backup cronjobs
kubectl get cronjobs -A | grep minio

# Check Prometheus targets
kubectl exec -n monitoring prometheus-0 -- wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | jq -r '.data.activeTargets[] | select(.labels.app=="svc-messaging") | "\(.labels.kubernetes_namespace): \(.health)"'
```
