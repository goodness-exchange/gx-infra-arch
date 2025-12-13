# Plan Comparison Analysis

**Date:** December 13, 2025
**Comparing:**
- `GX-Blockchain-Enterprise-Migration-Plan-v2.md` (Previous Plan - Dec 11, 2025)
- `RESTRUCTURING_PLAN.md` (Current Audit Plan - Dec 13, 2025)

---

## IP Address Mapping Decision

### Adopted Server Assignment (v2 Plan Mapping)

| VPS | IP Address | Role | Specs |
|-----|------------|------|-------|
| VPS-1 | 72.60.210.201 | MainNet Node 1 (Primary) + Monitoring | High-Spec (8 vCPU / 32GB) |
| VPS-2 | 72.61.116.210 | MainNet Node 2 | High-Spec (8 vCPU / 32GB) |
| VPS-3 | 72.61.81.3 | MainNet Node 3 + Backup | High-Spec (8 vCPU / 32GB) |
| VPS-4 | 217.196.51.190 | DevNet + TestNet (Standalone) | High-Spec (8 vCPU / 32GB) |
| VPS-5 | 195.35.36.174 | Website + Partner Simulator | Low-Spec (2 vCPU / 8GB) |

**Decision:** The comprehensive plan v3.0 uses the v2 plan's IP address mapping as requested by the user.

---

## Comparison Matrix

### Items in BOTH Plans

| Item | v2 Plan | Current Audit Plan | Notes |
|------|---------|-------------------|-------|
| Environment Separation | Yes | Yes | Aligned |
| 3-node MainNet HA | Yes | Yes | Aligned |
| TestNet on separate server | Yes | Yes | Aligned |
| Google Drive Backup | Yes | Yes | Aligned |
| rclone Configuration | Yes | Yes | More detail in current |
| Pod Anti-Affinity | Yes | Yes | More YAML in v2 |
| Node Labeling | Yes | Yes | Aligned |
| Firewall Hardening | Yes | Yes | More detail in current |
| Fabric Component Distribution | Yes | Yes | Aligned |
| Monitoring Enhancement | Yes | Yes | Aligned |

### Items ONLY in Previous Plan v2

| Item | Description | Should Include |
|------|-------------|----------------|
| **CA Architecture Section** | Detailed CA hierarchy diagram, certificate types, rotation procedures | YES - Important |
| **Industry Best Practices Tables** | Fabric, K8s, Docker, CA, Database best practices with status | YES - Useful reference |
| **PodDisruptionBudget YAML** | Complete YAML for orderer-pdb, peer-org1-pdb, peer-org2-pdb | YES - Critical for HA |
| **NetworkPolicy YAML** | Complete fabric-isolation policy with ingress/egress rules | YES - Security |
| **TLS Configuration Standards** | Minimum TLS 1.2, cipher suites | YES - Security |
| **Install Docker on VPS-3** | Note about VPS-3 missing Docker | VERIFY - My audit shows VPS-5 missing Docker |
| **Comprehensive Test Scripts** | 7 detailed test scripts (connectivity, K8s, Fabric, E2E, HA) | YES - Essential |
| **Cloudflare Integration** | DNS verification, settings recommendations, page rules | YES - Useful |
| **Operational Runbooks** | Emergency contacts, quick reference, incident response | YES - Essential |
| **Certificate Rotation Procedure** | Bash script for cert rotation, monitoring | YES - Important |
| **Pre-Migration Checklist** | Detailed checklist with checkboxes | YES - Useful |
| **Post-Migration Validation** | Comprehensive validation checklist | YES - Essential |
| **K8s CronJob for Backup** | YAML for automated backup CronJob | YES - Enhancement |

### Items ONLY in Current Audit Plan

| Item | Description | Critical Level |
|------|-------------|----------------|
| **Duplicate Fabric Discovery** | VPS-3 running BOTH Docker Compose AND K8s Fabric | CRITICAL |
| **70GB Docker Build Cache** | VPS-3 has 70GB reclaimable space | CRITICAL |
| **79% Disk Usage on VPS-3** | Immediate capacity issue | CRITICAL |
| **Backend Service Health Issues** | svc-tokenomics 0/3, multiple services 1/3 | HIGH |
| **Outbox-submitter Restarts** | MainNet: 140 restarts, TestNet: 1353 restarts | HIGH |
| **SSH Key Authentication** | Detailed implementation for all servers | HIGH |
| **Apache HTTPD Cleanup** | Running unnecessarily on VPS-2, 3, 5 | MEDIUM |
| **Work Record Tracking** | Daily documentation requirement | LOW |

---

## Reconciliation Decisions

### 1. IP Address Mapping
**Decision:** Use v2 plan mapping (VPS-1=72.60.210.201, etc.) as per user request.

### 2. Phase Structure
**Decision:** Merge into 6 phases:
- Phase 0: Emergency Stabilization (NEW - not in v2)
- Phase 1: Pre-Migration Preparation
- Phase 2: Security Hardening
- Phase 3: Architecture Restructuring
- Phase 4: Backup Implementation
- Phase 5: Testing & Validation
- Phase 6: Monitoring & Operations

### 3. Docker on VPS-3
**Clarification:**
- v2 plan shows VPS-3 (72.61.81.3) has no Docker
- This is confirmed - Docker needs installation for MainNet Node 3
- **Resolution:** 72.61.81.3 (VPS-3) requires Docker installation

### 4. Test Scripts
**Decision:** Include all 7 test scripts from v2 with updated IP mappings

### 5. Emergency Tasks
**Decision:** Add Phase 0 for critical issues found in current audit:
- Disk cleanup on VPS-3 (72.60.210.201)
- Stop duplicate Docker Compose Fabric
- Investigate backend service health

### 6. Kubernetes Configurations
**Decision:** Include all YAML from v2:
- PodDisruptionBudgets
- NetworkPolicies
- Anti-Affinity rules
- Node labels

---

## Combined Plan Summary

| Phase | Duration | Source |
|-------|----------|--------|
| Phase 0: Emergency Stabilization | Day 1-2 | Current Audit (NEW) |
| Phase 1: Pre-Migration Preparation | Day 2-3 | v2 Plan |
| Phase 2: Security Hardening | Day 3-5 | Both Plans |
| Phase 3: Infrastructure Setup | Day 5-8 | v2 Plan |
| Phase 4: Architecture Restructuring | Day 8-14 | Both Plans |
| Phase 5: Backup Implementation | Day 7-10 | Both Plans |
| Phase 6: Testing & Validation | Day 14-16 | v2 Plan |
| Phase 7: Monitoring & Operations | Day 16-18 | Both Plans |

**Total Duration:** ~18 working days (vs 12-14 in current plan)

---

## Action Items for Combined Plan

1. [x] Use v2 IP/VPS mapping (as per user request)
2. [x] Add Phase 0 for emergency stabilization
3. [x] Include CA architecture section from v2
4. [x] Include all YAML configurations from v2
5. [x] Include all 7 test scripts from v2 (with v2 IP mappings)
6. [x] Include Cloudflare section from v2
7. [x] Include operational runbooks from v2
8. [x] Add Docker installation for VPS-3 (72.61.81.3)
9. [x] Add backend service health investigation
10. [x] Add duplicate Fabric cleanup procedures

---

*End of Comparison Analysis*
