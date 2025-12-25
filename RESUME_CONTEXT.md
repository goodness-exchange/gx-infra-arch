# Resume Context - December 25, 2025 (Updated)

## Current Task: Environment Sync & Deployment Promotion

User identified that we were incorrectly fixing MainNet directly without following proper DevNet → TestNet → MainNet promotion workflow. Now working on syncing all environments.

---

## Environment Audit Results

### Docker Image Discrepancies

| Service | DevNet | TestNet | MainNet | Status |
|---------|--------|---------|---------|--------|
| gx-wallet-frontend | `:https` | `:testnet` | `:mainnet-auth-fix` | ❌ ALL DIFFERENT |
| svc-identity | `:devnet-fix` | `:2.1.9` | `:2.1.9` | ❌ DevNet different |
| svc-messaging | `:conv-fix` | `:conv-fix` | `:conv-fix` | ✅ Synced |
| svc-admin | `:2.1.15` | `:2.1.15` | `:2.1.15` | ✅ Synced |
| svc-tokenomics | `:2.1.5` | `:2.1.5` | `:2.1.5` | ✅ Synced |

### Service Availability Issues

| Service | DevNet | TestNet | MainNet |
|---------|--------|---------|---------|
| svc-admin | ⚠️ 0/1 NOT READY | ✅ Ready | ✅ Ready |
| svc-tokenomics | ⚠️ 0/1 NOT READY | ✅ Ready | ✅ Ready |
| svc-governance | ❌ Missing | ❌ Missing | ✅ Deployed |
| svc-loanpool | ❌ Missing | ❌ Missing | ✅ Deployed |
| svc-organization | ❌ Missing | ❌ Missing | ✅ Deployed |
| svc-tax | ❌ Missing | ❌ Missing | ✅ Deployed |

### svc-identity Version Analysis (IN PROGRESS)

Registry tags found:
- `svc-identity`: 2.1.5, 2.1.6, 2.1.7, 2.1.8, 2.1.9, 2.2.0, 2.3.0, latest, devnet-latest
- `gx-svc-identity`: phase2, phase2-fixed, phase2-v2, phase3-v1, phase3-v2, phase4-v1, phase4-v2, devnet-fix

Image creation timestamps:
- svc-identity:2.1.9 - Created: 2025-12-24T02:27:11 (older)
- gx-svc-identity:devnet-fix - Created: 2025-12-24T15:09:32 (newer, ~13 hours later)

**Analysis needed**: Determine which contains the latest fixes.

---

## User Decisions Made

1. **Deploy missing services to DevNet/TestNet**: svc-governance, svc-loanpool, svc-organization, svc-tax (needed for coin grants and allocation testing)

2. **svc-identity version**: Use whichever is latest/working (audit timestamps)

3. **Version tag strategy**: Single version with `<env>` suffix (e.g., `v2.2.0-devnet`, `v2.2.0-testnet`, `v2.2.0-mainnet`)

---

## Pending Tasks

1. ⏳ Audit svc-identity versions to determine latest correct version
2. ⏸️ Establish version tag strategy (v2.2.0-<env>)
3. ⏸️ Deploy missing services to DevNet (governance, loanpool, organization, tax)
4. ⏸️ Deploy missing services to TestNet (governance, loanpool, organization, tax)
5. ⏸️ Fix DevNet svc-admin (not ready)
6. ⏸️ Fix DevNet svc-tokenomics (not ready)
7. ⏸️ Build unified frontend with all fixes
8. ⏸️ Sync all environments with correct images
9. ⏸️ Design comprehensive test user data structure
10. ⏸️ Create test data for DevNet and TestNet
11. ⏸️ Verify all functionality on DevNet
12. ⏸️ Document deployment promotion workflow

---

## Previous Session Completed Tasks

1. ✅ Deploy messaging to MainNet
2. ✅ Update frontend with messaging UI
3. ✅ Fix Redis authentication issue
4. ✅ Fix testnet redis-secret URL
5. ✅ Set up MinIO credentials as secrets
6. ✅ Configure MinIO backups
7. ✅ Add Prometheus monitoring and alerts
8. ✅ Fix mainnet network routing (iptables DNAT for ports 80/443)
9. ✅ Add Cloudflare DNS A records
10. ✅ Fix NEXTAUTH_SECRET missing on mainnet frontend
11. ✅ Fix login "Invalid Credentials" error (internal K8s routing for NextAuth)

---

## Key URLs

| Environment | Frontend | API |
|-------------|----------|-----|
| MainNet | https://wallet.gxcoin.money | https://api.gxcoin.money |
| TestNet | https://testnet.gxcoin.money | https://testnet.gxcoin.money |
| DevNet | https://devnet.gxcoin.money | https://devnet.gxcoin.money |

---

## Quick Commands

```bash
# Check all pods across environments
for ns in backend-devnet backend-testnet backend-mainnet; do
  echo "=== $ns ===" && kubectl get pods -n $ns
done

# Check service health
for ns in backend-devnet backend-testnet backend-mainnet; do
  echo "=== $ns ==="
  kubectl exec -n $ns deploy/svc-identity -- wget -qO- http://127.0.0.1:3001/health 2>/dev/null || echo "svc-identity: FAILED"
done

# Check image versions
for ns in backend-devnet backend-testnet backend-mainnet; do
  echo "=== $ns ===" && kubectl get deploy -n $ns -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image'
done
```

---

## Resume Instructions

When resuming, continue with:
1. Complete svc-identity version audit (compare image contents/timestamps)
2. Proceed with environment sync following the pending tasks list
