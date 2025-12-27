# Work Record - December 27, 2025

## Session Summary
**Date:** 2025-12-27
**Focus:** Admin Dashboard Enterprise Features - Frontend RBAC UI & Enforcement

---

## Resuming from December 26, 2025

### Previous Session Completed
1. **Dashboard Metrics API** (svc-admin v2.2.2)
   - Dashboard service, controller, routes
   - 6 API endpoints for dashboard stats

2. **Frontend Dashboard UI** (gx-admin-frontend v1.0.3)
   - Metric cards, charts, activity feed

3. **Enterprise RBAC System Backend** (svc-admin v2.3.0)
   - 125 permissions seeded across 6 categories
   - 79 role-permission mappings for 5 roles
   - 17 RBAC API endpoints

### Current Deployment Status
| Service | Version | Namespace | Status |
|---------|---------|-----------|--------|
| svc-admin | v2.4.0 | backend-devnet | Running |
| gx-admin-frontend | v1.0.6 | backend-devnet | Running |

---

## Today's Objectives

### Priority 1: Frontend Role Management UI
- [x] Role list page with permission counts
- [x] Role detail view with permission matrix
- [x] Permission categories grid
- [x] My Access tab for current admin
- [ ] Permission assignment interface
- [ ] Admin role management

### Priority 2: RBAC Enforcement
- [x] Apply requirePermission middleware to existing endpoints
- [x] User management endpoints
- [x] Dashboard endpoints
- [x] Approval endpoints
- [x] Deployment endpoints
- [x] Notification/Webhook endpoints

### Priority 3: User Management Enhancements
- [ ] Enhanced user detail view
- [ ] User activity timeline
- [ ] Device/session history

---

## Progress Log

### RBAC Frontend Implementation

**1. Created RBAC Type Definitions** (`src/types/rbac.ts`)
- `AdminRole` type with 6 roles: SUPER_OWNER, SUPER_ADMIN, ADMIN, MODERATOR, DEVELOPER, AUDITOR
- `PermissionCategory` type: USER, FINANCIAL, AUDIT, SYSTEM, CONFIG, DEPLOYMENT
- `RiskLevel` type: LOW, MEDIUM, HIGH, CRITICAL
- `Permission` interface with full schema
- `RoleSummary`, `RoleDetails`, `AdminPermissionSummary` interfaces
- Display configuration constants for UI rendering

**2. Created RBAC TanStack Query Hooks** (`src/hooks/use-rbac.ts`)
- `usePermissions()` - Get all system permissions
- `useRoles()` - Get role summaries with permission counts
- `useRoleDetails(role)` - Get detailed permissions for a role
- `useMyPermissions()` - Get current admin's permissions
- `useAdminPermissions(adminId)` - Get specific admin's permissions
- Mutation hooks for grant/revoke/update operations

**3. Created Roles & Permissions Pages**
- Main page (`/dashboard/roles/page.tsx`) with 3 tabs:
  - Roles tab: Role cards with permission counts
  - Permissions tab: All system permissions with filtering
  - My Access tab: Current admin's permission summary
- Role detail page (`/dashboard/roles/[roleId]/page.tsx`):
  - Stats cards (total, MFA, approval, high-risk counts)
  - Permissions organized by category with collapsible sections
  - Permission removal interface for SUPER_OWNER

**4. Created Supporting Components**
- `roles-tab.tsx` - Role listing with RoleCard components
- `roles-table.tsx` - Role comparison table
- `permissions-tab.tsx` - Permission management view
- `permissions-table.tsx` - Searchable, filterable permissions list
- `permission-categories-grid.tsx` - Category summary cards
- `my-access-tab.tsx` - Current admin permission display
- `role-detail-content.tsx` - Role detail presentation

**5. Added Navigation**
- Added "Roles & Permissions" to sidebar under System section
- ShieldCheck icon from lucide-react

**6. ESLint Compliance Fixes**
- Fixed `@typescript-eslint/no-empty-object-type` error
- Fixed duplicate React imports
- Extracted components to reduce function complexity (< 10)
- Split large files to stay under 300 lines

**7. Build and Deployment**
- Built frontend v1.0.5 (initial RBAC UI)
- Built frontend v1.0.6 (admin role assignment)
- Docker images pushed to registry
- Deployed to backend-devnet namespace

### Admin Role Assignment Interface

**8. Updated Admin Types** (`src/types/admin.ts`)
- Fixed AdminRole to match backend: SUPER_OWNER, SUPER_ADMIN, ADMIN, MODERATOR, DEVELOPER, AUDITOR
- Removed deprecated SUPPORT and READONLY roles
- Added level property to ADMIN_ROLE_CONFIG for role hierarchy
- Exported getRoleLevel helper function

**9. Added Admin Management Hooks** (`src/hooks/use-admins.ts`)
- `useUpdateAdminRole()` - Update admin role via RBAC endpoint
- `useActivateAdmin()` - Activate admin account
- `useDeactivateAdmin()` - Deactivate admin account

**10. Created Role Change Dialog** (`_components/role-change-dialog.tsx`)
- Modal for changing admin roles
- Role hierarchy enforcement (users can only assign roles below their level)
- Radio group selection with role descriptions
- Confirmation before role change

**11. Updated Admin Management Components**
- AdminsTable: Added "Change Role" action in dropdown menu
- AdminRoleBadge: Refactored to use ADMIN_ROLE_CONFIG
- CreateAdminPage: Updated role options to use new role types
- AdminsPage: Integrated RoleChangeDialog with canManage permission check

### Backend RBAC Enforcement (svc-admin v2.4.0)

**12. Admin Routes** (`admin.routes.ts`)
Applied permission-based access control to all admin routes:
- System Administration: SUPER_OWNER only for bootstrap/treasury, config:limit:set for parameters
- System Control: system:pause:all, system:resume:all for critical operations
- Admin Management: admin:view:all, admin:create:all
- User Management: user:view:all, user:approve:all, user:reject:all, user:freeze:all, user:unfreeze:all

**13. Dashboard Routes** (`dashboard.routes.ts`)
All endpoints now require `report:view:dashboard` permission:
- GET /stats, /user-growth, /new-registrations
- GET /transaction-volume, /user-distribution, /recent-activity

**14. Deployment Routes** (`deployment.routes.ts`)
- View operations: deployment:view:all
- Promote: deployment:testnet:deploy
- Execute: SUPER_OWNER + deployment:mainnet:deploy (CRITICAL)
- Rollback: SUPER_OWNER + deployment:rollback:all

**15. Approval Routes** (`approval.routes.ts`)
- Create approval: Authenticated only (no special permission)
- View operations: approval:view:all
- Vote: SUPER_OWNER + approval:approve:all
- Execute: SUPER_OWNER only

**16. Notification Routes** (`notification.routes.ts`)
- Webhook view: webhook:view:all
- Webhook create: webhook:create:all (requires MFA)
- Webhook update: webhook:update:all (requires MFA)
- Webhook delete: webhook:delete:all (requires MFA)

---

## Challenges and Solutions

### Challenge 1: ESLint Complexity Rules
**Problem:** ESLint rule `complexity` limited functions to max 10 branches. RolesPage and RoleDetailPage exceeded this limit.
**Solution:** Extracted presentation logic into separate components (RolesTab, PermissionsTab, MyAccessTab, RoleDetailContent), keeping main pages simple.

### Challenge 2: File Line Limits
**Problem:** ESLint max-lines rule limited files to 300 lines. roles/page.tsx grew to 371 lines.
**Solution:** Extracted RolesTable, PermissionsTable, and PermissionCategoriesGrid into separate files.

### Challenge 3: Empty Interface Extension
**Problem:** `@typescript-eslint/no-empty-object-type` error for `interface GetRoleDetailsResponse extends RoleDetails {}`
**Solution:** Changed to type alias: `export type GetRoleDetailsResponse = RoleDetails;`

### Challenge 4: Permission Code Mismatches
**Problem:** Some route files used incorrect permission codes that didn't exist in the seed file (e.g., `approval:view` instead of `approval:view:all`).
**Solution:** Cross-referenced all permission codes with `seed-permissions.ts` and updated to correct format: `module:action:scope` (e.g., `user:view:all`, `webhook:create:all`).

---

## Commits Made

### gx-admin-frontend (development branch)

| Commit | Message |
|--------|---------|
| `da4349e` | feat(types): add RBAC type definitions |
| `c220de9` | feat(hooks): add RBAC TanStack Query hooks |
| `faf79f9` | feat(dashboard): add Roles & Permissions management UI |
| `65c0dda` | feat(navigation): add Roles & Permissions to sidebar |
| `2afd1ec` | fix(types): update AdminRole to match backend RBAC system |
| `aea69e1` | feat(hooks): add admin role management hooks |
| `0faa6df` | feat(admins): add role change dialog and update admin management |

**Pushed to origin/development successfully.**

### gx-protocol-backend (development branch)

| Commit | Message |
|--------|---------|
| `7ab2158` | feat(svc-admin): apply RBAC enforcement to admin routes |
| `e07d943` | feat(svc-admin): apply RBAC enforcement to dashboard routes |
| `e936a46` | feat(svc-admin): apply RBAC enforcement to deployment routes |
| `f1d10a3` | feat(svc-admin): apply RBAC enforcement to approval routes |
| `4d07113` | feat(svc-admin): apply RBAC enforcement to notification routes |

**Pushed to origin/development successfully.**

---

## Deployment Summary

| Service | Version | Changes |
|---------|---------|---------|
| svc-admin | v2.4.0 | RBAC enforcement on all routes |
| svc-admin | v1.4.0-fix1 | Audit log API (Phase 4) |
| gx-admin-frontend | v1.0.6 | Role management UI, admin role assignment |
| gx-admin-frontend | v1.1.0 | Permission assignment interface (Phase 1) |
| gx-admin-frontend | v1.2.0 | Admin role management (Phase 2) |
| gx-admin-frontend | v1.3.0 | Enhanced user detail view (Phase 3) |
| gx-admin-frontend | v1.4.0 | Audit log hooks (Phase 4) |

---

## RBAC Enforcement Testing (DevNet)

**17. Permission Seeding**
- Re-seeded 27 permissions with correct codes (module:action:scope format)
- Created 71 role-permission mappings
- Cleared RBAC cache and restarted svc-admin

**18. SUPER_OWNER Access Tests** (All PASS)
| Endpoint | Permission | Result |
|----------|------------|--------|
| Dashboard Stats | report:view:dashboard | ✅ PASS |
| List Users | user:view:all | ✅ PASS |
| List Admins | admin:view:all | ✅ PASS |
| System Status | system:health:view | ✅ PASS |
| List Approvals | approval:view:all | ✅ PASS |
| List Deployments | deployment:view:all | ✅ PASS |
| Unauthenticated Access | - | ✅ Blocked |

**19. ADMIN Role Permission Tests** (All PASS)
| Endpoint | Expected | Result |
|----------|----------|--------|
| List Users | Granted | ✅ PASS |
| Dashboard Stats | Granted | ✅ PASS |
| Pending Approvals | Blocked | ✅ PASS |
| Execute Deployment | Blocked | ✅ PASS |
| Rollback Deployment | Blocked | ✅ PASS |
| Pause System | Blocked | ✅ PASS |
| Create Admin | Blocked | ✅ PASS |

---

---

## Phase 1 Completion Log (Permission Assignment Interface)

### Challenges Faced

**Challenge 5: ESLint Function Complexity (AdminPermissionsEditor)**
- **Problem:** AdminPermissionsEditor had complexity of 17 (limit: 10) due to conditional rendering and multiple state handlers
- **Solution:** Extracted LoadingState, ErrorState, StatsGrid as separate components. Further extracted AdminPermissionsTabs for the tabbed content area. Final complexity: 8

**Challenge 6: File Size After Prettier Formatting**
- **Problem:** role-permissions-editor.tsx grew from 150 to 330+ lines after Prettier expanded condensed JSX
- **Solution:** Extracted RoleAddDialog and RoleRemoveDialog into separate files

**Challenge 7: Component Import Consolidation**
- **Problem:** ESLint no-duplicate-imports flagged separate `import type` and `import` statements from same module
- **Solution:** Combined into single imports: `import { type Permission, CATEGORY_DISPLAY } from "@/types/rbac"`

**Challenge 8: AdminRoleConfig Type Missing**
- **Problem:** AdminRoleConfig type was defined but not exported from admin.ts
- **Solution:** Added explicit `export type AdminRoleConfig` to types/admin.ts

### Key Design Decisions

1. **Component Extraction Pattern**: Dialogs and tabs extracted to separate files to maintain < 300 lines per file
2. **Dual Permission View**: Admin permissions split into Role (inherited) vs Custom (grantable/revokable)
3. **Risk Level Badges**: Color-coded badges (green/blue/orange/red) for permission risk levels
4. **Category Grouping**: All permissions organized by 6 categories with visual icons

---

## Session Status: COMPLETED

---

# DevNet Development Roadmap

## Phase Overview

| Phase | Feature | Status | Target Version |
|-------|---------|--------|----------------|
| 1 | Permission Assignment Interface | ✅ Complete | v1.1.0 |
| 2 | Admin Role Management | ✅ Complete | v1.2.0 |
| 3 | Enhanced User Detail View | ✅ Complete | v1.3.0 |
| 4 | User Activity Timeline | ✅ Complete | v1.4.0 |
| 5 | Device/Session History | ⏳ Pending | v1.5.0 |

---

## Phase 1: Permission Assignment Interface ✅ COMPLETED

### 1.1 Backend API Enhancements ✅
Backend API already complete from previous session:
- [x] Bulk permission assignment endpoint (POST /rbac/admins/:id/permissions)
- [x] Permission search/filter endpoint (GET /rbac/permissions)
- [x] Permission category summary endpoint (GET /rbac/permissions/summary)
- [x] Role permission management endpoints

### 1.2 Frontend Permission Picker Component ✅
Created `src/components/rbac/permission-picker.tsx`:
- [x] Category-based permission grouping with tabs
- [x] Search and filter functionality
- [x] Multi-select with checkbox support
- [x] Selected permissions display with count
- [x] Risk level indicators (LOW, MEDIUM, HIGH, CRITICAL badges)
- [x] MFA requirement badges
- [x] Approval requirement badges

### 1.3 Admin Permission Editor ✅
Created admin permission management components:
- [x] `admin-permissions-editor.tsx` - Main editor for admin permissions
- [x] `admin-permissions-tabs.tsx` - Tabbed view (All/Role/Custom)
- [x] `admin-grant-dialog.tsx` - Dialog for granting new permissions
- [x] `admin-revoke-dialog.tsx` - Confirmation for revoking permissions
- [x] `permissions-by-category.tsx` - Grouped permission display
- [x] Admin detail page (`/dashboard/admins/[adminId]/page.tsx`)
- [x] Stats display (role, custom, high-risk, MFA counts)

### 1.4 Role Permission Editor ✅
Created role permission management components:
- [x] `role-permissions-editor.tsx` - Editor for role permissions
- [x] `role-add-dialog.tsx` - Dialog for adding permissions to role
- [x] `role-remove-dialog.tsx` - Confirmation for removing role permissions
- [x] Updated `role-detail-content.tsx` with RolePermissionsEditor
- [x] Category icons and permission item components

### 1.5 Testing & Deployment ✅
- [x] ESLint compliance (complexity < 10, lines < 300)
- [x] Build verification passed
- [x] Docker image built (v1.1.0)
- [x] Pushed to cluster registry
- [x] Deployed to DevNet (backend-devnet namespace)

### Phase 1 Commit
| Commit | Message |
|--------|---------|
| `3cc1be4` | feat(rbac): implement permission assignment interface |

### Components Created (19 files, +1852 lines)
```
src/components/rbac/
├── admin-grant-dialog.tsx
├── admin-permissions-editor.tsx
├── admin-permissions-tabs.tsx
├── admin-revoke-dialog.tsx
├── index.ts
├── permission-picker.tsx
├── permissions-by-category.tsx
├── role-add-dialog.tsx
├── role-permissions-editor.tsx
└── role-remove-dialog.tsx

src/app/(main)/dashboard/admins/[adminId]/
├── page.tsx
└── _components/
    ├── admin-header.tsx
    ├── admin-profile-tab.tsx
    └── index.ts

src/app/(main)/dashboard/roles/_components/
├── category-icons.tsx (new)
├── role-detail-content.tsx (modified)
└── role-permission-item.tsx (new)
```

---

## Phase 2: Admin Role Management ✅ COMPLETED

### 2.1 Admin CRUD Operations ✅
- [x] Create admin form with validation (existing)
- [x] Edit admin profile page (EditAdminDialog)
- [x] Deactivate/reactivate admin (StatusToggleDialog)
- [x] Delete admin with safeguards (DeleteAdminDialog - username confirmation)

### 2.2 Admin List Enhancements ✅
- [x] Advanced filtering (role, status, MFA, search)
- [x] AdminFiltersBar component with multi-criteria filtering
- [x] Modular filter helper functions for ESLint compliance
- [x] Filtered count display (X of Y)

### 2.3 Admin Detail Page ✅
- [x] Profile information section (existing AdminProfileTab)
- [x] Role and permissions summary (AdminPermissionsTab)
- [x] Session history (new AdminSessionsTab)
- [x] Login stats (last login, IP, failed attempts, lock status)

### 2.4 Testing & Deployment ✅
- [x] ESLint compliance (complexity < 10, lines < 300)
- [x] Build verification passed
- [x] Docker image built (v1.2.0)
- [x] Pushed to cluster registry
- [x] Deployed to DevNet (backend-devnet namespace)

### Phase 2 Commits
| Commit | Message |
|--------|---------|
| `df039c2` | feat(admin-dashboard): implement Phase 2 admin role management |

### Components Created/Modified (9 files, +716 lines)
```
src/app/(main)/dashboard/admins/
├── page.tsx (modified - integrated dialogs & filters)
├── _components/
│   ├── admin-filters.tsx (new - 151 lines)
│   ├── admins-table.tsx (modified - status toggle)
│   ├── delete-admin-dialog.tsx (new - 103 lines)
│   ├── edit-admin-dialog.tsx (new - 130 lines)
│   └── status-toggle-dialog.tsx (new - 95 lines)
└── [adminId]/
    ├── page.tsx (modified - added Sessions tab)
    └── _components/
        ├── admin-sessions-tab.tsx (new - 136 lines)
        └── index.ts (modified - export)
```

### Technical Improvements
1. **Modular Filter Functions**: Extracted `matchesRole()`, `matchesStatus()`, `matchesMfa()`, `matchesSearch()` to reduce complexity
2. **Type-Safe Filter Interface**: `AdminFilters` with proper union types
3. **Nullish Coalescing**: Used `??` throughout for safer defaults
4. **Username Confirmation**: Delete dialog requires typing admin username as safeguard

---

## Phase 3: Enhanced User Detail View ✅ COMPLETED

### 3.1 User Profile Redesign ✅
- [x] Tabbed interface (Profile, Documents, Activity, Wallet)
- [x] Personal info and blockchain identity cards
- [x] Registered addresses display
- [x] Responsive 3-column grid layout

### 3.2 User Actions Panel ✅
- [x] StatusCard: Account status, lock state, on-chain status, KYC docs count
- [x] ActionsCard: Approve/Deny KYC, Freeze/Unfreeze buttons
- [x] FreezeDetailsCard: Freeze reason, timestamp, actor, notes
- [x] Dropdown menu placeholder for Send Notification, Reset Password/MFA

### 3.3 User Documents Section ✅
- [x] KycSummaryCard: Document count stats, ID vs selfie breakdown
- [x] DocumentCard: Type icons, external link to storage
- [x] Empty state for users without KYC documents
- [x] Denial info card for denied users

### 3.4 User Activity Tab ✅
- [x] Activity summary cards (Total Events, KYC Reviewed, Account Locked, On-Chain)
- [x] ActivityTimeline component with icon and color coding
- [x] Dynamically built from user review/freeze history
- [x] EmptyActivityState for new users

### 3.5 User Wallet Tab ✅
- [x] Placeholder balance cards (GXC, Staked, Sent, Received)
- [x] Placeholder transaction history
- [x] Info card about future tokenomics integration
- [x] WalletNotAvailable state for users without Fabric ID

### 3.6 Testing & Deployment ✅
- [x] ESLint compliance (extracted StatusCard, ActionsCard, FreezeDetailsCard)
- [x] Build verification passed
- [x] Docker image built (v1.3.0)
- [x] Pushed to cluster registry
- [x] Deployed to DevNet (backend-devnet namespace)

### Phase 3 Commits
| Commit | Message |
|--------|---------|
| `060d61b` | feat(user-detail): implement Phase 3 enhanced user detail view |

### Components Created (7 files, +968 lines)
```
src/app/(main)/dashboard/users/[id]/
├── page.tsx (modified - tabbed interface, 4-column grid)
└── _components/
    ├── index.ts (new)
    ├── user-profile-tab.tsx (new - 132 lines)
    ├── user-documents-tab.tsx (new - ~160 lines)
    ├── user-activity-tab.tsx (new - ~230 lines)
    ├── user-wallet-tab.tsx (new - 122 lines)
    └── user-actions-panel.tsx (new - ~207 lines)
```

### Technical Improvements
1. **Component Extraction**: StatusCard, ActionsCard, FreezeDetailsCard extracted for ESLint complexity compliance
2. **Dynamic Activity Timeline**: Built from user.reviewedAt, user.lockedAt timestamps
3. **Document Categorization**: ID documents vs selfie photos with different icons/colors
4. **Placeholder Wallet Tab**: Ready for future tokenomics API integration

---

## Phase 4: User Activity Timeline ✅ COMPLETED

### 4.1 Activity Tracking Backend ✅
- [x] Activity event types definition (27 AuditEventType values)
- [x] Activity logging service (audit.service.ts)
- [x] Activity query API with pagination (8 endpoints)
- [x] Activity statistics and summary endpoints

### 4.2 Backend API Implementation ✅
Created comprehensive audit log API in svc-admin:
- [x] `apps/svc-admin/src/types/audit.types.ts` - Type definitions
- [x] `apps/svc-admin/src/services/audit.service.ts` - Query service with name enrichment
- [x] `apps/svc-admin/src/controllers/audit.controller.ts` - HTTP handlers
- [x] `apps/svc-admin/src/routes/audit.routes.ts` - Protected routes with RBAC

**API Endpoints Created:**
| Endpoint | Description |
|----------|-------------|
| GET /api/v1/admin/audit/logs | Query logs with filters |
| GET /api/v1/admin/audit/users/:profileId | User-specific logs |
| GET /api/v1/admin/audit/users/:profileId/summary | User activity summary |
| GET /api/v1/admin/audit/admins/:adminId | Admin action logs |
| GET /api/v1/admin/audit/admins/:adminId/summary | Admin activity summary |
| GET /api/v1/admin/audit/recent | Recent activity |
| GET /api/v1/admin/audit/stats | Activity statistics |
| GET /api/v1/admin/audit/event-types | Available event types |

### 4.3 Frontend Hooks ✅
- [x] Extended `src/types/audit.ts` with full type coverage
- [x] Rewrote `src/hooks/use-audit-logs.ts` with TanStack Query integration
- [x] Added helper functions: buildAuditFilterParams, formatAuditTime
- [x] Event display configuration with severity/category colors

### 4.4 Testing & Deployment ✅
- [x] Backend built successfully
- [x] Docker image: svc-admin:v1.4.0-fix1
- [x] Frontend built: gx-admin-frontend:v1.4.0
- [x] Deployed to DevNet
- [x] All 8 API endpoints tested and verified

### Phase 4 Commits
| Commit | Message |
|--------|---------|
| `67e4dd5` | feat(svc-admin): add audit log type definitions |
| `9b1cd34` | feat(svc-admin): implement audit log service |
| `8394f95` | feat(svc-admin): add audit log HTTP controller |
| `5af4e2d` | feat(svc-admin): register audit routes with RBAC protection |
| `aa08df7` | fix(svc-admin): correct Prisma model names in audit service |
| `5f02800` | feat(types): extend audit types with event tracking support |
| `94c9085` | feat(hooks): implement comprehensive audit log hooks |

### Technical Details
1. **AuditEventType Coverage**: 27 event types across 11 categories
2. **RBAC Protection**: All audit endpoints require `audit:view:all` permission
3. **Name Enrichment**: Logs enriched with actor/target names from UserProfile and AdminUser
4. **SHA-256 Hash**: Event hash generation for tamper detection

---

## Phase 5: Device/Session History

### 5.1 Session Tracking Backend
- [ ] Device fingerprinting
- [ ] Session metadata collection
- [ ] Session query API
- [ ] Suspicious activity detection

### 5.2 Session Management UI
- [ ] Active sessions list
- [ ] Device information display
- [ ] Terminate session action
- [ ] Terminate all sessions

### 5.3 Security Features
- [ ] Unusual login alerts
- [ ] Location-based anomaly detection
- [ ] Session timeout configuration
- [ ] Force re-authentication

### 5.4 Testing & Deployment
- [ ] Test session tracking
- [ ] Build and deploy to DevNet

---

## Post-Phase Testing (DevNet)

After all 5 phases are complete:
- [ ] End-to-end RBAC testing
- [ ] Permission matrix verification
- [ ] Admin workflow testing
- [ ] User management workflow testing
- [ ] Performance testing
- [ ] Security audit

## TestNet Promotion

Only after DevNet testing is complete:
- [ ] Review all DevNet test results
- [ ] Create promotion request
- [ ] Execute promotion to TestNet
- [ ] Verify TestNet deployment
