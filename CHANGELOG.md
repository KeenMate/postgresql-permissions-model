# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.19.1] - 2026-03-04

### Changed

#### MFA Failures Count Toward Auto-Lockout

Failed MFA challenges now count toward the auto-lockout threshold alongside wrong password attempts. Previously, invalid TOTP codes only raised 38004 with no lockout consequence, making 6-digit TOTP codes a brute-force vector.

**Changes:**

- `unsecure.check_and_auto_lock_user` — now counts both `user_login_failed` and `mfa_challenge_failed` events within the lockout window
- `auth.verify_mfa_challenge` — on failure (Case 3), logs `mfa_challenge_failed` event and calls `check_and_auto_lock_user`. Raises 33004 (user locked) if threshold exceeded, otherwise raises 38004 (MFA challenge failed)

## [2.19.0] - 2026-03-04

### Added

#### MFA Recovery Code Reset

New function to regenerate recovery codes for a confirmed MFA enrollment, without requiring disable + re-enroll. Addresses the scenario where a user has lost their recovery codes but still has their TOTP authenticator.

**New function:**

| Function | Layer | Description |
|----------|-------|-------------|
| `auth.reset_mfa(_updated_by, _user_id, _correlation_id, _target_user_id, _mfa_type_code, _request_context)` | auth | Generates 10 new recovery codes, replaces existing hashes. Returns plaintext codes (shown once). Validates enrollment exists (38002) and is confirmed (38003). Permission: `mfa.reset_mfa`. |

**New permission:** `mfa.reset_mfa`

**New event code:** 10097 `mfa_recovery_reset` — logged when recovery codes are regenerated.

#### MFA Policy (Enforcement Rules)

Scope-based rules table (`auth.mfa_policy`) to signal whether MFA is required for specific users, groups, tenants, or globally. Resolution: most-specific scope wins (user > group > tenant > global). Without any rules, MFA remains optional (default: `false`).

**New table:** `auth.mfa_policy` — columns: `mfa_policy_id` (identity PK), `tenant_id` (FK → tenant, nullable), `user_group_id` (FK → user_group, nullable), `user_id` (FK → user_info, nullable), `mfa_required boolean`, audit columns. Unique index on `coalesce(tenant_id, -1), coalesce(user_group_id, -1), coalesce(user_id, -1)` for null-safe deduplication.

**New functions:**

| Function | Layer | Description |
|----------|-------|-------------|
| `auth.create_mfa_policy(...)` | auth | Creates an MFA enforcement rule. Scope determined by which params are null (all null = global). Permission: `mfa.mfa_policy.create_mfa_policy`. |
| `auth.delete_mfa_policy(...)` | auth | Deletes a policy rule. Validates existence (38007). Permission: `mfa.mfa_policy.delete_mfa_policy`. |
| `auth.get_mfa_policies(...)` | auth | Lists policies filtered by optional scope params. Permission: `mfa.mfa_policy.get_mfa_policies`. |
| `unsecure.is_mfa_required(_target_user_id, _tenant_id)` | unsecure | Resolves whether MFA is required. No permission check (login flow). Resolution: user-level → group-level (`bool_or` via `get_cached_group_ids`) → tenant-level → global → `false`. |
| `auth.is_mfa_required(_user_id, _correlation_id, _target_user_id, _tenant_id)` | auth | Permission-checked wrapper (reuses `mfa.get_mfa_status` permission). |

**New permissions** (hierarchy under `mfa.mfa_policy`):
- `mfa.mfa_policy` (parent, not assignable)
- `mfa.mfa_policy.create_mfa_policy`, `mfa.mfa_policy.delete_mfa_policy`, `mfa.mfa_policy.get_mfa_policies`

**New event codes:**

| Code | Event | Description |
|------|-------|-------------|
| 10095 | mfa_policy_created | MFA policy rule was created |
| 10096 | mfa_policy_deleted | MFA policy rule was deleted |

**New error code:**

| Code | Function | Description |
|------|----------|-------------|
| 38007 | error.raise_38007 | MFA policy does not exist |

**Tests:** `tests/test_mfa_policy/` — 10 test files covering reset MFA (happy path + error cases 38002/38003), global/tenant/group/user policy creation with scope resolution cascade, policy deletion with fallback verification, get_mfa_policies filtering, error cases (38007 not found, unique violation on duplicate scope).

**Files:** `039_mfa_policy.sql`, `040_functions_mfa_policy.sql`

## [2.18.0] - 2026-03-04

### Added

#### Auto-Lockout on Repeated Login Failures

Automatic account lockout after too many failed login attempts within a configurable time window. Previously, locking was manual-only via `auth.lock_user()`.

**New functions:**

| Function | Layer | Description |
|----------|-------|-------------|
| `unsecure.check_and_auto_lock_user(_updated_by, _correlation_id, _target_user_id, _request_context)` | unsecure | Counts recent `user_login_failed` events within the configured window. If threshold exceeded: sets `is_locked=true`, clears permission cache, logs `user_auto_locked` event. Returns true if locked, false otherwise. Skips if user already locked (no duplicate events). |
| `auth.record_login_failure(_user_id, _correlation_id, _target_user_id, _email, _request_context)` | auth | Called by app after password hash mismatch (DB never sees raw passwords). Logs `user_login_failed` event with reason `wrong_password`, then calls `check_and_auto_lock_user()`. Raises 33004 (user locked) if auto-locked, otherwise raises 52103 (invalid credentials). Requires `authentication.get_data` permission. |

**New system parameters** (`const.sys_param`):

| group_code | code | default | description |
|------------|------|---------|-------------|
| `login_lockout` | `max_failed_attempts` | `5` | Number of failures before auto-lock |
| `login_lockout` | `window_minutes` | `15` | Time window in minutes for counting failures |

**New event code:** 10083 `user_auto_locked` — logged when auto-lockout triggers.

**Login flow (app layer):**
1. App calls `auth.get_user_by_email_for_authentication(email)` → gets user + password hash
2. App verifies password hash
3. If wrong: app calls `auth.record_login_failure()` → DB counts failures, maybe auto-locks
4. If correct + MFA enabled: proceed to MFA challenge flow

**Tests:** `tests/test_auto_lockout/` — 5 tests covering sys_param verification, single failure (no lock), threshold triggers lock + event, no duplicate events on already-locked user, window expiry (old failures not counted).

**Files:** `036_tables_mfa.sql`, `037_functions_auto_lockout.sql`

#### Multi-Factor Authentication (TOTP)

Complete MFA implementation with two-step enrollment (enroll → confirm), TOTP verification, and one-time recovery codes. The DB stores app-encrypted TOTP secrets and SHA-256 hashed recovery codes — the DB never sees raw TOTP secrets or codes.

**New tables:**

| Table | Description |
|-------|-------------|
| `const.mfa_type` | MFA type lookup (currently `totp` only). Columns: `code` (PK), `title`, `is_active`. |
| `auth.user_mfa` | User MFA enrollment. Columns: `user_mfa_id` (identity PK), `user_id` (FK → user_info, cascade), `mfa_type_code` (FK → mfa_type), `secret_encrypted`, `is_enabled`, `is_confirmed`, `recovery_codes text[]` (SHA-256 hashes), `enrolled_at`, `confirmed_at`, audit columns. Unique on `(user_id, mfa_type_code)`. |

**New extension:** `pgcrypto` (schema `ext`) — used for `digest()` to hash recovery codes.

**New token state:** `'invalid'` added to `const.token_state` — used for invalidating previous MFA tokens.

**New functions:**

| Function | Layer | Description |
|----------|-------|-------------|
| `auth.enroll_mfa(...)` | auth | Initiates TOTP enrollment. App provides encrypted secret. Generates 10 recovery codes (returned plaintext once, stored as SHA-256 hashes). Rejects if already confirmed (38001), replaces pending enrollments. Permission: `mfa.enroll_mfa`. |
| `auth.confirm_mfa_enrollment(...)` | auth | Confirms enrollment. App verifies TOTP code externally, passes `_code_is_valid boolean`. Sets `is_enabled=true, is_confirmed=true`. Permission: `mfa.confirm_mfa_enrollment`. |
| `auth.disable_mfa(...)` | auth | Deletes MFA enrollment record. Logs `mfa_disabled` event. Permission: `mfa.disable_mfa`. |
| `auth.get_mfa_status(...)` | auth | Returns enrollment state + `recovery_codes_remaining`. Permission: `mfa.get_mfa_status`. |
| `auth.create_mfa_challenge(...)` | auth | Creates time-limited token (type=`mfa`, channel=`app`, 300s default). Invalidates previous valid MFA tokens. Validates MFA is enrolled + confirmed + enabled. Permission: `mfa.create_mfa_challenge`. |
| `auth.verify_mfa_challenge(...)` | auth | Three-way verification: (1) `_code_is_valid=true` → TOTP passed, (2) `_code_is_valid=false` + `_recovery_code` → hash-match against stored codes (consumed on use), (3) neither → token marked failed + error 38004. Permission: `mfa.verify_mfa_challenge`. |

**New permissions** (hierarchy under `mfa`):
- `mfa` (parent, not assignable)
- `mfa.enroll_mfa`, `mfa.confirm_mfa_enrollment`, `mfa.disable_mfa`, `mfa.get_mfa_status`, `mfa.create_mfa_challenge`, `mfa.verify_mfa_challenge`

**New event codes:**

| Code | Event | Description |
|------|-------|-------------|
| 10090 | mfa_enrolled | MFA enrollment was initiated |
| 10091 | mfa_enrollment_confirmed | MFA enrollment was confirmed with a valid code |
| 10092 | mfa_challenge_created | MFA challenge token was created |
| 10093 | mfa_challenge_passed | MFA challenge was successfully verified |
| 10094 | mfa_recovery_used | MFA recovery code was used to pass challenge |

**New error codes** (category `mfa_error`, range 38001-38999):

| Code | Function | Description |
|------|----------|-------------|
| 38001 | error.raise_38001 | MFA is already enrolled and confirmed for this type |
| 38002 | error.raise_38002 | MFA is not enrolled for this type |
| 38003 | error.raise_38003 | MFA enrollment is not confirmed |
| 38004 | error.raise_38004 | The provided MFA code is not valid |
| 38005 | error.raise_38005 | MFA verification is required |
| 38006 | error.raise_38006 | MFA type does not exist or is inactive |

**Tests:** `tests/test_mfa/` — 8 test files covering enrollment (recovery codes, pending state), re-enrollment blocking (38001), confirmation (valid + invalid code), status query, challenge + TOTP verification, recovery code verification (count decrement), disable (record deletion), error cases (non-existent token, invalid code, non-enrolled user, invalid MFA type).

**Files:** `036_tables_mfa.sql`, `038_functions_mfa.sql`

## [2.17.0] - 2026-03-02

### Added

#### User Blacklist for Deleted Users

New `auth.user_blacklist` table and supporting functions to prevent re-creation of deleted or banned users. Blocks re-registration by username (email/direct) and re-authentication by provider identity (OAuth/SAML). Supports both automatic blacklisting on deletion and manual blacklisting by admins.

**New table:** `auth.user_blacklist` — stores blacklisted usernames, provider UIDs/OIDs, original user_id for audit trail, reason, and admin notes. Constraint ensures at least one identifier (username, provider_uid, or provider_oid) is present.

**New functions:**

| Function | Layer | Description |
|----------|-------|-------------|
| `unsecure.check_user_blacklist(_username, _provider_code, _provider_uid, _provider_oid)` | unsecure | Core check — returns true if any identifier matches a blacklist entry |
| `unsecure.blacklist_user(...)` | unsecure | Inserts a single blacklist entry with journal event 10080 |
| `unsecure.blacklist_user_identities(_target_user_id, _reason)` | unsecure | Bulk: reads user_info + all user_identity rows, blacklists each. Must be called before deletion. |
| `auth.add_to_blacklist(...)` | auth | Permission-checked (`users.manage_blacklist`). Manual blacklisting with reason and notes. |
| `auth.remove_from_blacklist(_blacklist_id)` | auth | Permission-checked (`users.manage_blacklist`). Deletes entry, journals event 10081. |
| `auth.search_blacklist(_search_text, _reason, _page, _page_size)` | auth | Permission-checked (`users.search_blacklist`). Paginated search across username, provider_uid, provider_oid, notes. |
| `auth.is_blacklisted(...)` | auth | Public wrapper around `unsecure.check_user_blacklist`. No permission check (used in creation paths). |

**New permissions:** `users.manage_blacklist`, `users.search_blacklist`

**New event codes:** 10080 (user_blacklisted), 10081 (user_unblacklisted), 10082 (user_creation_blocked)

**New error codes:** 33018 (err_user_blacklisted), 33019 (err_identity_blacklisted). Legacy aliases: `error.raise_52115` → 33018, `error.raise_52116` → 33019.

**Blacklist checks added to existing functions:**

| Function | Check | Blocks |
|----------|-------|--------|
| `unsecure.create_user_info()` | Username blacklist | Email/direct registration |
| `unsecure.create_service_user_info()` | Username blacklist | Service user creation |
| `unsecure.create_user_identity()` | Provider uid/oid blacklist | Defense-in-depth for any identity creation path |
| `auth.ensure_user_from_provider()` | Provider uid/oid blacklist (before user creation) | OAuth/SAML re-authentication |

**Auto-blacklist on delete:** `unsecure.delete_user_by_id()` gains `_blacklist boolean default false` parameter. When true, calls `blacklist_user_identities()` before the DELETE (while FK data still exists). Function converted from `language sql` to `language plpgsql` to support this.

**Tests:** `tests/test_user_blacklist/` — 21 tests covering manual blacklisting, creation blocking (username + provider identity), auto-blacklist on delete, unblacklist + re-creation, search/pagination, edge cases (duplicates, service users, case-insensitive matching, default no-blacklist on delete).

**Files:** `013_tables_auth.sql`, `016_functions_error.sql`, `019_functions_unsecure.sql`, `020_functions_auth_user.sql`, `022_functions_auth_permission.sql`, `029_seed_data.sql`

### Fixed

#### `auth.delete_user_info()` — was deleting user groups instead of users

The function body was a copy-paste from `auth.delete_user_group` — it referenced `auth.user_group`, `_user_group_id`, and journaled event 13003 (group_deleted). Fixed to correctly reference `auth.user_info`, `_target_user_id`, use proper error checks (33001 user not found, 33002 user is system), call `unsecure.delete_user_by_id()`, and journal event 10003 (user_deleted). Also added `_blacklist boolean default false` parameter for the new blacklist feature.

## [2.16.0] - 2026-03-02

### Added

#### Bulk Ensure Functions for App Bootstrapping

Four new `auth.ensure_*` functions for idempotent bulk creation of permissions, permission sets, user groups, and group mappings. Designed for application startup — call them every time the app boots and they create only what's missing, skip what already exists, and optionally remove what's no longer defined.

| Function | Description |
|----------|-------------|
| `auth.ensure_permissions(_created_by, _user_id, _correlation_id, _permissions jsonb, _source, _is_final_state)` | Create/sync hierarchical permissions from JSONB array. Processes parents before children. |
| `auth.ensure_perm_sets(_created_by, _user_id, _correlation_id, _perm_sets jsonb, _source, _tenant_id, _is_final_state)` | Create/sync permission sets with their permissions. Adds missing permissions to existing sets. |
| `auth.ensure_user_groups(_created_by, _user_id, _correlation_id, _user_groups jsonb, _tenant_id, _source, _is_final_state)` | Create/sync user groups. Always sets `is_system=false`. |
| `auth.ensure_user_group_mappings(_created_by, _user_id, _correlation_id, _mappings jsonb, _tenant_id, _is_final_state)` | Create/sync group mappings. Supports both `user_group_id` and `user_group_title` for group resolution. |

All functions return the full set of processed entities (existing + newly created), not just the new ones.

**Example — app bootstrap:**
```sql
-- Define permissions (idempotent — safe to call every startup)
select * from auth.ensure_permissions('app', 1, null, '[
    {"title": "Documents", "is_assignable": false},
    {"title": "Read documents", "parent_code": "documents"},
    {"title": "Write documents", "parent_code": "documents"}
]', 'my_app');

-- Define permission sets
select * from auth.ensure_perm_sets('app', 1, null, '[
    {"title": "Document Viewer", "permissions": ["documents.read_documents"]},
    {"title": "Document Editor", "permissions": ["documents.read_documents", "documents.write_documents"]}
]', 'my_app');

-- Define groups
select * from auth.ensure_user_groups('app', 1, null, '[
    {"title": "Document Editors"},
    {"title": "Document Viewers", "is_external": true}
]', 1, 'my_app');
```

**Files:** `022_functions_auth_permission.sql`, `021_functions_auth_group.sql`

**Tests:** `tests/test_ensure_functions/` — 26 tests covering creation, idempotency, hierarchy, flags, mixed existing+new, return sets, error handling.

#### `_is_final_state` — Declarative State Sync for Ensure Functions

New `_is_final_state boolean default false` parameter on all 4 ensure functions. When `true`, the input represents the **complete desired state** — items not in the input are removed (scoped by `_source` to prevent cross-module interference).

**Scoping rules:**
- `_source` is **required** when `_is_final_state = true` (raises exception if null)
- Only items matching the same `_source` (+ `_tenant_id` where applicable) are candidates for removal
- Items with a different source or null source are never touched
- For `ensure_user_group_mappings`: scoped by `(user_group_id, provider_code)` pairs in the input — no `_source` needed

**What each function removes when `_is_final_state = true`:**

| Function | Removes |
|----------|---------|
| `ensure_permissions` | Permissions with same source not in input. Deepest-first (children before parents). Cleans up `perm_set_perm` and `permission_assignment` rows. Updates `has_children` flags. |
| `ensure_perm_sets` | **Within each set:** removes permissions not in that set's `permissions[]` array. **Whole sets:** removes perm sets with same source+tenant not in input. Cleans up `permission_assignment` rows, invalidates affected users' permission cache. |
| `ensure_user_groups` | Non-system groups with same source+tenant not in input. Cleans up `user_group_mapping` and `permission_assignment` rows. `trg_cache_user_group_before_delete` trigger handles cache invalidation. |
| `ensure_user_group_mappings` | For each `(group, provider)` combo in input, removes mappings not in the input set. Invalidates affected users' permission cache. |

**Example — remove "Write documents" permission on next deploy:**
```sql
-- Only list what should exist — "Write documents" will be removed
select * from auth.ensure_permissions('app', 1, null, '[
    {"title": "Documents", "is_assignable": false},
    {"title": "Read documents", "parent_code": "documents"}
]', 'my_app', _is_final_state := true);
```

All removals are journaled (events `12003` permission_deleted, `12022` perm_set_deleted, `13003` group_deleted, `13021` group_mapping_deleted).

**Additional permission checks:** `permissions.delete_permission` (ensure_permissions), `permissions.delete_permission_set` (ensure_perm_sets), `groups.delete_group` (ensure_user_groups), `groups.delete_mapping` (ensure_user_group_mappings).

**Tests:** 19 additional tests (27–45) covering null source error, default-no-remove, same-source removal, different-source safety, reference cleanup, within-set permission sync, (group,provider) scoping, role-based mappings.

#### `source` Column on `auth.user_group`

New `source text default null` column on `auth.user_group` table, matching the existing pattern on `auth.permission` and `auth.perm_set`. Used as the deletion boundary for `_is_final_state` scoping.

- `013_tables_auth.sql` — column added after `nrm_search_data`
- `017_functions_triggers.sql` — `source` included in search value calculation
- `019_functions_unsecure.sql` — `_source` parameter added to `unsecure.create_user_group`
- `021_functions_auth_group.sql` — `_source` parameter added to `auth.create_user_group`

## [2.15.0] - 2026-03-01

### Changed

#### Event ID reassignment — resolve collisions between modules

Language/translation events collided with maintenance and resource access events (both used ranges 17001-17999, 18001-18999, 35001-35999). Since `029_seed_data.sql` runs before `030_tables_language.sql`, the `ON CONFLICT DO NOTHING` silently skipped language/translation event inserts.

Reassigned to free ranges:

| Module | Old Range | New Range |
|--------|-----------|-----------|
| Language Events | 17001-17999 | 20001-20999 |
| Translation Events | 18001-18999 | 21001-21999 |
| Language/Translation Errors | 35001-35999 | 37001-37999 |

Error functions renamed: `error.raise_35001` → `error.raise_37001`, `error.raise_35002` → `error.raise_37002`.

Files updated: `030_tables_language.sql`, `031_functions_language.sql`, `032_functions_translation.sql`, `tests/test_language_translation/001_tables_and_seed_data.sql`, `tests/test_language_translation/006_constraints_journal_errors.sql`.

#### Column rename — `ua_*` → `nrm_*`

Renamed all `ua_` prefixed columns to `nrm_` (normalized) for consistency:
- `auth.user_info.ua_username` → `nrm_username`
- `public.translation.ua_search_data` → `nrm_search_data`
- Index `ix_translation_ua_search` → `ix_translation_nrm_search`

#### `unsecure.create_perm_set_as_system` — bypass `is_assignable` check

Converted from a thin SQL wrapper (that delegated to `unsecure.create_perm_set`) to a standalone plpgsql function that inserts directly, bypassing the `is_assignable` check on permissions. This allows system perm sets like `system_admin` to include non-assignable permissions (e.g., `resources`) without making them permanently assignable.

#### Makefile — all targets now use debee

Replaced `./tests/run-tests.sh` and `./exec-sql.sh` references with `debee.ps1` calls. Added `FILTER=` support to `make test`.

### Fixed

- `unsecure.recalculate_user_permissions` — added `drop table if exists` before creating temp table `__temp_users_groups_permissions` to prevent failure when called twice in the same transaction
- Resource access test suite — fixed column names, type mismatches, missing FK cleanup, and missing perm set creation for non-default tenants

## [2.14.0] - 2026-02-28

### Added

#### Resource Access (ACL) System

Resource-level authorization layered on top of RBAC. While RBAC controls what actions a user can perform globally, the ACL system controls which specific resources they can act on.

**Tables** (`034_tables_resource_access.sql`):
- `const.resource_type` — registry of valid resource types (e.g. `folder`, `document`)
- `const.resource_access_flag` — registry of access flags (`read`, `write`, `delete`, `share`); extensible with custom flags
- `auth.resource_access` — core ACL table, list-partitioned by `resource_type`. One row = one flag for one user/group on one resource. Supports both grants (`is_deny=false`) and explicit denies (`is_deny=true`)

**Functions** (`035_functions_resource_access.sql`):

| Function | Purpose |
|----------|---------|
| `auth.has_resource_access()` | Check if user has a flag on a resource (deny-overrides algorithm) |
| `auth.filter_accessible_resources()` | Bulk filter — returns subset of resource IDs user can access |
| `auth.get_resource_access_flags()` | Returns all effective flags + source (direct/group name) |
| `auth.grant_resource_access()` | Grant flags to user or group (idempotent upsert) |
| `auth.deny_resource_access()` | Explicit deny on user (overrides all group grants) |
| `auth.revoke_resource_access()` | Revoke specific flags or all flags |
| `auth.revoke_all_resource_access()` | Remove all ACL rows for a resource (cleanup on delete) |
| `auth.get_resource_grants()` | List all grants/denies on a resource |
| `auth.get_user_accessible_resources()` | List resources a user can access |
| `auth.create_resource_type()` | Register new resource type + auto-create partition |
| `unsecure.validate_resource_type()` | Validate resource type exists and is active |
| `unsecure.validate_access_flags()` | Validate all flags in array exist |
| `unsecure.ensure_resource_access_partition()` | Create partition for resource type if missing |

**Access check algorithm** (priority order):
1. System user (id=1) — always allowed
2. Tenant owner — always allowed
3. User-level deny — blocked, overrides everything
4. User-level grant — allowed
5. Group-level grant (via active group membership) — allowed
6. No matching row — denied

**Deny model**: User-level only. Cannot deny groups. Per-flag granularity. Explicit denies override all group grants for that user.

**RBAC permissions** (`022_functions_auth_permission.sql`):
- New parent: `Resources` (not assignable)
- Children: `resources.create_resource_type`, `resources.grant_access`, `resources.deny_access`, `resources.revoke_access`, `resources.update_access`, `resources.get_grants`
- New perm set: "Resource manager" (resources + journal read)
- Updated perm sets: "System admin" and "Full admin" now include `resources`

**Error codes** (`016_functions_error.sql`):
- `35001` — User has no access to resource
- `35002` — Neither user_id nor user_group_id provided
- `35003` — Resource type not found or inactive
- `35004` — Access flag not found

**Event codes** (`029_seed_data.sql`):
- `18001` resource_type_created, `18010` resource_access_granted, `18011` resource_access_revoked, `18012` resource_access_denied, `18013` resource_access_bulk_revoked

**Test suite** (`tests/test_resource_access/`):
- 8 test files covering grant/revoke, has_resource_access, deny-overrides, bulk filter, effective flags/grants, tenant isolation, cascade deletes
- Transaction isolation mode

#### Provider Capability Flags

New columns on `auth.provider` to control group mapping and sync behavior per provider (`013_tables_auth.sql`, `024_functions_auth_provider.sql`):

- `allows_group_mapping` (boolean, default false) — whether provider supports group mapping
- `allows_group_sync` (boolean, default false) — whether provider supports group sync
- Constraint: `allows_group_sync` requires `allows_group_mapping`
- New validation functions: `auth.validate_provider_allows_group_mapping()`, `auth.validate_provider_allows_group_sync()`
- `auth.create_provider()`, `auth.update_provider()`, `auth.ensure_provider()` updated with new parameters
- `auth.create_user_group_mapping()` now validates provider allows group mapping
- `auth.sync_user_group_members()` now validates provider allows group sync
- `unsecure.resolve_user_groups_from_provider()` skips mapping resolution when provider doesn't allow it
- New error codes: `33016` (provider does not allow group mapping), `33017` (provider does not allow group sync)

### Changed

- Reset `auth.tenant` and `auth.user_group` identity sequences to start at 1000 (IDs 1-999 reserved for system use) (`029_seed_data.sql`)

## [2.13.0] - 2026-02-28

### Changed

#### Debee Integration — execSql and runTests

Replaced standalone `exec-sql.sh` and `tests/run-tests.sh` with debee's built-in `execSql` and `runTests` operations. All three debee implementations (PowerShell, Bash, Python) now handle SQL execution and test running natively.

- **`execSql`** — Execute SQL files, inline commands, or open interactive psql sessions directly through debee
- **`runTests`** — Full test framework with suite directories, `test.json` manifests, isolation modes, shared setup scripts, and `--test-filter` filtering

#### Test Suite Restructure

Converted all 11 flat test files (`test_*.sql`) into suite directories following the debee test framework conventions:

| Suite | Tests | Description |
|-------|-------|-------------|
| `test_connection/` | 1 | Basic database connectivity |
| `test_connectivity/` | 3 | Connectivity with temp table operations |
| `test_provider_crud/` | 19 | Provider CRUD, journaling, capability flags |
| `test_registration_login_events/` | 21 | Registration, login events, request_context |
| `test_disabled_locked_users/` | 9 | Disabled/locked user blocking, cache clearing |
| `test_permission_cache_invalidation/` | 12 | Cache invalidation (soft/hard), owner functions |
| `test_short_code/` | 16 | Hierarchical permission short codes |
| `test_correlation_id/` | 5 | Correlation ID flow and search filtering |
| `test_event_code_management/` | 20 | Event category/code/message CRUD, system protection |
| `test_language_translation/` | 25 | Language CRUD, translations, copy/overwrite |
| `test_group_members_and_delete_tenant/` | 5 | Group member queries, tenant deletion |
| `test_auth_group_member_tenant/` | 11 | Auth-layer group/tenant with permission checks |
| `test_search_functions/` | 14 | All search functions: pagination, filtering |

Each suite directory contains:
- `test.json` — Manifest with name, description, `isolation: "transaction"`
- `000_setup.sql` — Search path and test data setup
- `001_*.sql` – `008_*.sql` — Grouped test files
- `900_cleanup.sql` — Cleanup (transaction rollback handles data automatically)

Global test ordering controlled by `tests/tests.json`.

### Removed

- `exec-sql.sh` — Replaced by `debee execSql`
- `tests/run-tests.sh` — Replaced by `debee runTests`
- All flat `tests/test_*.sql` files — Replaced by suite directories

## [2.12.0] - 2026-02-26

### Added

#### Storage Mode Switch — Offload Journal & User Events via pg_notify

Journal messages and user events can now be routed to an external system (e.g., ClickHouse) via PostgreSQL's LISTEN/NOTIFY instead of (or in addition to) being stored locally. This is controlled independently for each subsystem via `const.sys_param`.

**New sys_param entries:**

| group_code | code | default | values |
|------------|------|---------|--------|
| `journal` | `storage_mode` | `local` | `local`, `notify`, `both` |
| `user_event` | `storage_mode` | `local` | `local`, `notify`, `both` |

**Storage modes:**

| Mode | Behavior |
|------|----------|
| `local` | INSERT into PostgreSQL only (current default, no behavior change) |
| `notify` | Fire `pg_notify` only, skip INSERT — data goes to external listener |
| `both` | INSERT into PostgreSQL AND fire `pg_notify` |

**New functions:**

| Function | Description |
|----------|-------------|
| `helpers.should_store_locally(_group_code)` | Returns true when storage_mode is `local` or `both` |
| `helpers.should_notify_storage(_group_code)` | Returns true when storage_mode is `notify` or `both` |
| `unsecure.notify_journal_event(...)` | Sends journal entry as JSON on `journal_events` channel |
| `unsecure.notify_user_event(...)` | Sends user event as JSON on `user_events` channel |

**Modified functions:**

- `public.create_journal_message()` — checks storage mode, fires notify if needed, skips INSERT in `notify` mode
- `unsecure.create_user_event()` — same pattern

**Notify channels:** `journal_events`, `user_events` (separate from existing `permission_changes`)

**Payload truncation:** pg_notify has an 8000 byte limit. If a payload exceeds ~7900 bytes, `data_payload`/`request_context` (or `event_data`/`request_context` for user events) are stripped and `"truncated": true` is added. Most payloads are well under 1KB.

**Note:** When mode is `notify`, search/query functions (`search_journal`, `get_journal_entry`, `search_user_events`, `get_user_audit_trail`, `get_security_events`) return empty results since data is not in PostgreSQL. The app should query the external store directly.

## [2.11.0] - 2026-02-26

### Changed

#### Request Context Consolidation

Replaced three separate text parameters (`_ip_address`, `_user_agent`, `_origin`) with a single `_request_context jsonb` parameter across all functions that accept request metadata. The same replacement applies to the corresponding table columns. This makes the system extensible — callers can pass any context fields (e.g., `device_id`, `geo_location`, `session_id`) without modifying function signatures.

#### Schema Changes

| Table | Change |
|-------|--------|
| `auth.user_event` | Replaced `ip_address text`, `user_agent text`, `origin text` columns with `request_context jsonb` |
| `auth.token` | Replaced `ip_address text`, `user_agent text`, `origin text` columns with `request_context jsonb` |
| `public.journal` | Added `request_context jsonb` column |

#### Function Signature Changes (22 functions)

All functions that previously accepted `_ip_address text, _user_agent text, _origin text` now accept `_request_context jsonb` instead:

**Core event functions:**
- `unsecure.create_user_event` — `_request_context jsonb default null` replaces three text params
- `auth.create_user_event` — same replacement, pass-through to unsecure

**User management (10 functions):**
- `auth.enable_user`, `auth.disable_user`, `auth.unlock_user`, `auth.lock_user`
- `auth.enable_user_identity`, `auth.disable_user_identity`
- `auth.update_user_password` (required, no default)
- `auth.register_user`
- `auth.get_user_by_email_for_authentication`
- `auth.ensure_user_from_provider`

**Token functions (6 functions):**
- `auth.set_token_as_used`, `auth.set_token_as_used_by_token`
- `auth.set_token_as_failed`, `auth.set_token_as_failed_by_token`
- `auth.validate_token`
- `public.validate_token`

**API key validation:**
- `auth.validate_api_key`

**Query/reporting return types updated:**
- `auth.search_user_events` — returns `__request_context jsonb` instead of three text columns
- `auth.get_user_audit_trail` — same replacement
- `auth.get_security_events` — same replacement

#### Journal Functions Extended

All journal creation functions now accept an optional `_request_context jsonb` parameter and store it in the new `public.journal.request_context` column:

- `public.create_journal_message`
- `public.create_journal_message_by_code`
- `public.create_journal_message_for_entity`
- `public.create_journal_message_for_entity_by_code`
- `public.get_journal_entry` — return type includes `__request_context jsonb`

#### Calling Convention

```sql
-- Standard usage
select auth.enable_user('admin', 1, 'corr-123', 42,
    _request_context := '{"ip_address": "192.168.1.1", "user_agent": "Mozilla/5.0", "origin": "https://app.example.com"}'::jsonb);

-- With custom fields (the whole point of this refactor)
select auth.register_user('admin', 1, 'corr-123', 'user@example.com', '$hash$', 'User Name',
    _request_context := jsonb_build_object(
        'ip_address', '192.168.1.1',
        'user_agent', 'Mozilla/5.0',
        'device_id', 'abc-123',
        'geo_location', 'Prague, CZ'
    ));

-- Without context (optional — defaults to null)
select auth.enable_user('admin', 1, 'corr-123', 42);
```

### Breaking Changes

- **Column renames on `auth.user_event` and `auth.token`**: `ip_address`, `user_agent`, `origin` columns replaced by `request_context jsonb`. Queries that read these columns must be updated.
- **Function signatures**: All 22 functions listed above have changed parameter lists. Callers passing positional arguments for the old three-param pattern must switch to the new `_request_context` parameter.
- **Return type changes**: `auth.search_user_events`, `auth.get_user_audit_trail`, `auth.get_security_events` now return `__request_context jsonb` instead of separate text columns.

**Files modified:** `013_tables_auth.sql`, `014_tables_stage.sql`, `018_functions_public.sql`, `019_functions_unsecure.sql`, `020_functions_auth_user.sql`, `025_functions_auth_token.sql`, `026_functions_auth_apikey.sql`, `028_functions_auth_event.sql`, `tests/test_registration_login_events.sql`

---

## [2.10.0] - 2026-02-23

### Added

#### Range Partitioning for Audit Tables

Both `public.journal` and `auth.user_event` are now range-partitioned by `created_at` (monthly). On busy systems these tables grow indefinitely; the old `DELETE WHERE created_at < threshold` purge was slow (row-by-row deletion, WAL bloat, index maintenance). Partitioning solves this with instant `DROP PARTITION` purges, automatic partition pruning on all date-filtered queries, and smaller per-partition indexes for faster inserts.

#### Schema Changes

| Change | Description |
|--------|-------------|
| `public.journal` PK | `journal_id` -> composite `(journal_id, created_at)` |
| `public.journal` | Added `partition by range (created_at)` |
| `auth.user_event` PK | `user_event_id` -> composite `(user_event_id, created_at)` |
| `auth.user_event` | Added `partition by range (created_at)` |
| `auth.token.user_event_id` FK | Dropped (partitioned tables require partition key in FK target; the FK also had `ON DELETE CASCADE` which would cascade-delete tokens when old event partitions are dropped) |
| New index `ix_user_event_created` | `auth.user_event (created_at desc)` |
| New index `ix_user_event_target_user` | `auth.user_event (target_user_id, created_at desc)` |
| Default partitions | `public.journal_default`, `auth.user_event_default` (safety net) |
| Initial partitions | 5 monthly partitions created at setup (-1 to +3 months from now) |

#### New Functions

| Function | Description |
|----------|-------------|
| `unsecure.ensure_audit_partitions(_months_ahead)` | Creates monthly partitions N months ahead for both tables. Idempotent. Reads default from `const.sys_param` (`partition.months_ahead`). |

#### New Seed Data

| Parameter | Value | Description |
|-----------|-------|-------------|
| `partition.months_ahead` | `3` | Default number of months to pre-create partitions |

### Changed

#### Purge Functions Rewritten for Partition Drops

`unsecure.purge_journal()` and `unsecure.purge_user_events()` now:
1. Calculate cutoff month from retention days
2. Find and drop partitions named `journal_YYYY_MM` / `user_event_YYYY_MM` older than cutoff
3. Fall back to `DELETE` on the default partition for safety
4. Call `ensure_audit_partitions()` to pre-create future months

#### Search Functions Optimized for Partition Pruning

`public.search_journal()` and `auth.search_user_events()` now pass `created_at` through the CTE to the join condition, enabling the planner to prune partitions on the re-join instead of scanning all partitions.

**Files modified:** `013_tables_auth.sql`, `014_tables_stage.sql`, `018_functions_public.sql`, `019_functions_unsecure.sql`, `028_functions_auth_event.sql`, `029_seed_data.sql`

---

## [2.9.0] - 2026-02-22

### Added

#### Source Tracking for Permissions, Permission Sets, Event Codes, and Event Categories

When inspecting `auth.permission` or `const.event_code` in a production system, there was no way to tell which rows came from the core permissions model vs. the application vs. a plugin. The new `source` column solves this.

#### Schema Changes

Added `source text default null` to four tables:

| Table | Description |
|-------|-------------|
| `auth.permission` | Track which module defined each permission |
| `auth.perm_set` | Track which module defined each permission set |
| `const.event_code` | Track which module defined each event code |
| `const.event_category` | Track which module defined each event category |

All core seed data is marked `source = 'core'`. Existing applications that don't specify a source get `null` — fully non-breaking.

**Files modified:** `012_tables_const.sql`, `013_tables_auth.sql`

#### Function Changes — Creation Chain

All permission and perm set creation functions now accept `_source text default null`, passed down through the chain:

| Function | File |
|----------|------|
| `unsecure.create_permission()` | `019_functions_unsecure.sql` |
| `unsecure.create_permission_as_system()` | `019_functions_unsecure.sql` |
| `auth.create_permission()` | `022_functions_auth_permission.sql` |
| `unsecure.create_perm_set()` | `019_functions_unsecure.sql` |
| `unsecure.create_perm_set_as_system()` | `019_functions_unsecure.sql` |
| `auth.create_perm_set()` | `022_functions_auth_permission.sql` |
| `public.create_event_code()` | `018_functions_public.sql` |
| `public.create_event_category()` | `018_functions_public.sql` |

`unsecure.copy_perm_set()` propagates `source` from the source perm set to the copy.

#### Function Changes — Query and Search

All query/search functions now return `__source text`:

| Function | File | Also added `_source` filter? |
|----------|------|------------------------------|
| `unsecure.get_all_permissions()` | `019_functions_unsecure.sql` | No |
| `auth.get_all_permissions()` | `022_functions_auth_permission.sql` | No |
| `unsecure.get_perm_sets()` | `019_functions_unsecure.sql` | No |
| `auth.get_perm_sets()` | `022_functions_auth_permission.sql` | No |
| `auth.search_permissions()` | `022_functions_auth_permission.sql` | Yes |
| `auth.search_perm_sets()` | `022_functions_auth_permission.sql` | Yes |
| `public.get_permissions_map()` | `022_functions_auth_permission.sql` | No |

#### View Changes

`auth.effective_permissions` — added `perm_set_source` and `permission_source` columns.

**Files modified:** `015_views.sql`

#### Search Trigger Changes

`triggers.calculate_permission_search_values()` and `triggers.calculate_perm_set_search_values()` now include `source` in `nrm_search_data`, so full-text search picks up source values.

**Files modified:** `017_functions_triggers.sql`

#### Seed Data

- All ~90 `create_permission_as_system()` calls in `seed_permission_data()` now pass `_source := 'core'`
- All ~19 `create_perm_set_as_system()` calls in `seed_permission_data()` now pass `_source := 'core'`
- All `INSERT INTO const.event_category` rows (15) now include `source = 'core'`
- All `INSERT INTO const.event_code` rows (~80) now include `source = 'core'`

**Files modified:** `022_functions_auth_permission.sql`, `029_seed_data.sql`

#### Usage Examples

```sql
-- All core permissions grouped by source
select source, count(*) from auth.permission group by source;

-- Application creates its own permission
select auth.create_permission('admin', 1, null, 'Export data', 'areas.admin',
    _source := 'myapp');

-- Search by source
select * from auth.search_permissions(1, null, _source := 'core');
select * from auth.search_perm_sets(1, null, _source := 'core');

-- Event codes by source
select source, count(*) from const.event_code group by source;
```

---

## [2.8.0] - 2026-02-21

### Added

#### Audit Infrastructure Improvements
Comprehensive improvements to the audit and logging subsystems: plugging journal gaps, adding admin action context tracking, data retention, and higher-level audit query functions.

#### 1. Journal Gaps Filled

**Group sync operations** — `auth.process_external_group_member_sync_by_mapping()` and `auth.process_external_group_member_sync()` performed bulk INSERT/UPDATE/DELETE on `auth.user_group_member` with zero audit trail. A scheduled sync job could add/remove dozens of users invisibly.

- `process_external_group_member_sync_by_mapping()` now creates a summary journal entry (event 13030 `group_members_synced`) recording `members_created`, `users_ensured`, `provider_code`, and `user_group_mapping_id`
- `process_external_group_member_sync()` now journals per-mapping deletions (event 13011 `group_member_removed`) with `members_deleted` count and `action: sync_cleanup` / `sync_cleanup_missing_mappings`

**Token batch expiration** — `unsecure.expire_tokens()` silently expired tokens with no audit trail.

- Rewritten from `language sql` to `language plpgsql` with `get diagnostics` to capture row count
- Now journals batch expirations (event 15003 `token_expired`) with `expired_count` and `action: batch_expiration`

**New event code:**

| ID | Code | Category | Description |
|----|------|----------|-------------|
| 13030 | `group_members_synced` | `group_event` | External group members synchronized from provider |

**Files modified:** `019_functions_unsecure.sql`, `021_functions_auth_group.sql`, `029_seed_data.sql`

#### 2. Admin Action Context (IP/User-Agent/Origin)

Six admin user management functions created journal entries but lacked IP/user-agent/origin tracking in `auth.user_event`. Each function now:
- Accepts optional `_ip_address text`, `_user_agent text`, `_origin text` parameters (all `DEFAULT NULL` — non-breaking change)
- Creates a `user_event` entry alongside the existing journal entry

| Function | user_event type |
|----------|----------------|
| `auth.enable_user()` | `user_enabled` |
| `auth.disable_user()` | `user_disabled` |
| `auth.unlock_user()` | `user_unlocked` |
| `auth.lock_user()` | `user_locked` |
| `auth.enable_user_identity()` | `identity_enabled` |
| `auth.disable_user_identity()` | `identity_disabled` |

**Files modified:** `020_functions_auth_user.sql`

#### 3. Data Retention & Cleanup

No mechanism existed for purging old audit data — both `journal` and `user_event` grew indefinitely.

**Configuration** — retention defaults added to `const.sys_param`:

| group_code | code | text_value |
|------------|------|------------|
| `journal` | `retention_days` | `365` |
| `user_event` | `retention_days` | `365` |

**New functions:**

| Function | Schema | Description |
|----------|--------|-------------|
| `unsecure.purge_journal()` | unsecure | Deletes journal entries older than specified/configured days |
| `unsecure.purge_user_events()` | unsecure | Deletes user events older than specified/configured days |
| `public.purge_audit_data()` | public | Permission-checked wrapper calling both purge functions, self-journals the purge action |

- `purge_audit_data()` requires `journal.purge_journal` permission
- If `_older_than_days` is null, reads from `const.sys_param` retention config
- The purge itself is journaled (event 17001 `audit_data_purged`) recording `journal_deleted` and `user_events_deleted` counts

**New permission:**

| Permission Code | Description |
|-----------------|-------------|
| `journal.purge_journal` | Purge old audit data |

Added to `system_admin` permission set.

**New event category and code:**

| ID | Code | Category | Description |
|----|------|----------|-------------|
| — | `maintenance_event` | — | New category (17001-17999) for system maintenance events |
| 17001 | `audit_data_purged` | `maintenance_event` | Old audit data was purged |

**Files modified:** `019_functions_unsecure.sql`, `018_functions_public.sql`, `022_functions_auth_permission.sql`, `029_seed_data.sql`

#### 4. Audit Summary Query Functions

Two new higher-level query functions for common audit needs:

**`auth.get_user_audit_trail()`** — Combined, paginated view of all audit activity for a specific user. UNIONs journal entries (matched via `keys @> {"user": target_user_id}`) with user events (matched via `target_user_id`). Returns unified rows with `__source` ('journal' or 'user_event'), resolved messages for journal entries, and IP/user-agent/origin for user events.

**`auth.get_security_events()`** — Aggregated, paginated view of security-relevant events across the system. Includes failed logins (`user_login_failed`), lockouts (`user_locked`, `user_disabled`), unlock/enable events, identity changes, and permission denials (journal event 32001). Returns source, requester/target user info, IP/user-agent, and event data.

Both functions require `authentication.read_user_events` permission and support date range filtering and pagination.

**Files modified:** `028_functions_auth_event.sql`

#### 5. Ensure Provider Function

New `auth.ensure_provider()` — idempotent provider creation following the same "ensure" pattern as `auth.ensure_user_info()`. Returns existing provider if found (no permission check), or creates a new one (requires `providers.create_provider`). Returns `__provider_id` and `__is_new` flag.

**Files modified:** `024_functions_auth_provider.sql`

#### 6. Composable Human Admin Permission Sets

Eight new permission sets that break down the monolithic `system_admin` into composable, human-facing roles. Each set grants only the permissions needed for a specific administrative function — assign multiple sets to a user or group for composite roles.

| Permission Set | Permissions | Use Case |
|---------------|-------------|----------|
| `User manager` | `users`, `authentication.read_user_events`, `journal.read_journal`, `journal.get_payload` | User CRUD, view user audit events |
| `Group manager` | `groups`, `journal.read_journal`, `journal.get_payload` | Group and membership management |
| `Permission manager` | `permissions`, `journal.read_journal`, `journal.get_payload` | Permission and perm set management |
| `Provider manager` | `providers`, `journal.read_journal`, `journal.get_payload` | Identity provider management |
| `Token manager` | `tokens.create_token`, `tokens.validate_token`, `tokens.set_as_used`, `token_configuration`, `journal.read_journal`, `journal.get_payload` | Token lifecycle and token type config |
| `Api key manager` | `api_keys`, `journal.read_journal`, `journal.get_payload` | API key management |
| `Auditor` | `journal`, `authentication.read_user_events`, `users.read_users`, `groups.get_group`, `groups.get_groups`, `tenants.read_tenants` | Read-only audit access across all entities |
| `Full admin` | All of the above combined + `tenants`, `journal.purge_journal`, `languages`, `translations`, `authentication.create_auth_event` | Complete administrative access |

All sets are `is_assignable = true` so they can be assigned to users or groups via `auth.assign_permission()`.

**New group:**

| Group ID | Name | Permission Set |
|----------|------|---------------|
| 3 | `Full admins` | `full_admin` |

Add users to the "Full admins" group for complete administrative access without using the `system_admin` perm set (which is reserved for the system superuser).

**Files modified:** `022_functions_auth_permission.sql`

### Fixed

#### Bug: Duplicate Email Check Bypassed in `auth.register_user()`
`__normalized_email` was declared but never assigned — stayed NULL. The duplicate check `ui.uid = lower(NULL)` always evaluated to false, so registering the same email twice bypassed the friendly error and hit a raw unique constraint violation instead.

Fix: added `__normalized_email := lower(trim(_email))` before the duplicate check.

**Files modified:** `020_functions_auth_user.sql`

#### Bug: `ON CONFLICT` Mismatch in `recalculate_user_groups()`
`ON CONFLICT (user_group_id, user_id)` didn't match the actual unique index `uq_user_group_member (user_group_id, user_id, coalesce(mapping_id, 0))`. PostgreSQL requires an exact match. Any `has_permission` call that triggered `recalculate_user_groups` for a user already in a default group would fail with `invalid_column_reference`.

Fix: changed to `ON CONFLICT (user_group_id, user_id, coalesce(mapping_id, 0))`.

**Files modified:** `019_functions_unsecure.sql`

---

## [2.7.0] - 2026-02-21

### Added

#### Dedicated Service Accounts (Least-Privilege System Users)
Previously the backend used `user_id:1` (system superuser) for all operations — registration, login, token ops, API key validation, etc. This user has a hardcoded bypass in `auth.has_permissions()` that returns `true` unconditionally. If a backend endpoint leaks this context, it has godmode over the entire system.

The system now ships with purpose-specific service accounts, each with only the permissions needed for its job. The user_id range 1-999 is reserved for system/service users (sequence starts at 1000).

**Service Accounts:**

| ID | Username | Display Name | Purpose | Key Permissions |
|----|----------|-------------|---------|-----------------|
| 1 | `system` | System | Seed/migration only (keeps `has_permissions` bypass, never used at runtime) | *(bypass)* |
| 2 | `svc_registrator` | Registrator | User registration flow | `users.register_user`, `users.add_to_default_groups`, `tokens.create_token` |
| 3 | `svc_authenticator` | Authenticator | Login & authentication flow | `authentication.get_data`, `authentication.ensure_permissions`, `authentication.get_users_groups_and_permissions`, `authentication.create_auth_event`, `tokens.validate_token`, `tokens.set_as_used` |
| 4 | `svc_token_manager` | Token Manager | Token lifecycle (password reset, email verification, etc.) | `tokens.create_token`, `tokens.validate_token`, `tokens.set_as_used` |
| 5 | `svc_api_gateway` | API Gateway | API key validation at the gateway/middleware level | `api_keys.validate_api_key` |
| 6 | `svc_group_syncer` | Group Syncer | Background external group member synchronization | `groups.get_groups`, `groups.get_members`, `groups.create_member`, `groups.delete_member`, `groups.get_mapping`, `users.register_user`, `users.add_to_default_groups` |
| 800 | `svc_data_processor` | Data Processor | Generic app-level data processing (recommended alternative to user_id 1) | *(none — app adds its own)* |

All service accounts: `user_type_code = 'service'`, `can_login = false`, `is_system = true`.

**Permission Sets:**

| Permission Set | Assigned To |
|----------------|-------------|
| `svc_registrator_permissions` | `svc_registrator` (2) |
| `svc_authenticator_permissions` | `svc_authenticator` (3) |
| `svc_token_permissions` | `svc_token_manager` (4) |
| `svc_api_gateway_permissions` | `svc_api_gateway` (5) |
| `svc_group_syncer_permissions` | `svc_group_syncer` (6) |
| `svc_data_processor_permissions` | `svc_data_processor` (800) |

**Design decisions:**
- `svc_registrator` also gets `tokens.create_token` — registration flows typically create email/phone verification tokens
- `svc_authenticator` also gets `tokens.validate_token` + `tokens.set_as_used` — verification link clicks go through the auth flow
- `svc_data_processor` (ID 800) ships with an empty permission set — applications add their own permissions to it. Recommended as the default backend service account instead of `user_id:1`
- Admin operations (enable/disable/lock users, manage groups, etc.) are done by human admins with permissions through group membership — no service account needed
- `auth.ensure_user_from_provider()` has no permission check by design (provider validation serves as authorization), so the authenticator doesn't need extra permissions for provider login

**Files modified:** `022_functions_auth_permission.sql`, `029_seed_data.sql`

### Fixed

#### Missing Permissions in Seed Data
Two authentication permissions were checked by existing functions but never created in `seed_permission_data()`:
- `authentication.ensure_permissions` — checked by `auth.ensure_groups_and_permissions()` but never seeded
- `authentication.get_users_groups_and_permissions` — checked by `auth.get_users_groups_and_permissions()` but never seeded (only `users.get_users_groups_and_permissions` existed under a different parent)

#### `system_admin` Permission Set Missing Token & Authentication Permissions
The `system_admin` perm set didn't include `tokens` or `authentication` parent permissions. Regular System Admin group members (not user_id:1) couldn't perform token or authentication operations. Added both to the permission set.

---

## [2.6.0] - 2026-02-20

### Added

#### Real-Time Permission Change Notifications (LISTEN/NOTIFY)
PostgreSQL pub/sub notifications for permission-relevant changes. Backends can `LISTEN permission_changes` to receive JSON notifications and push "refetch permissions" events to clients via SSE/WebSocket.

**New Functions:**

| Function | Schema | Description |
|----------|--------|-------------|
| `unsecure.notify_permission_change(_event, _tenant_id, _target_type, _target_id, _detail)` | unsecure | Builds JSON payload and calls `pg_notify('permission_changes', ...)` |
| `unsecure.invalidate_permission_users_cache(_updated_by, _permission_id)` | unsecure | Invalidates cache for all users affected by a permission change (direct, via perm_set, via group) |
| `unsecure.invalidate_users_permission_cache(_updated_by, _user_ids, _tenant_id)` | unsecure | Bulk cache invalidation for an array of user IDs |

**Notification Payload Format:**
```json
{
    "event": "group_member_added",
    "tenant_id": 1,
    "target_type": "user",
    "target_id": 42,
    "detail": { "group_id": 7 },
    "at": "2026-02-20T14:30:00Z"
}
```

**Notification Trigger Functions (triggers schema):**

| Trigger Function | Table | Events | Notification Events |
|-----------------|-------|--------|---------------------|
| `triggers.notify_permission_assignment` | `auth.permission_assignment` | INSERT, DELETE | `permission_assigned`, `permission_unassigned` |
| `triggers.notify_perm_set_perm` | `auth.perm_set_perm` | INSERT, DELETE | `perm_set_permissions_added`, `perm_set_permissions_removed` |
| `triggers.notify_user_group_member` | `auth.user_group_member` | INSERT, DELETE | `group_member_added`, `group_member_removed` |
| `triggers.notify_user_group` | `auth.user_group` | UPDATE, DELETE | `group_disabled`, `group_enabled`, `group_type_changed`, `group_deleted` |
| `triggers.notify_user_group_mapping` | `auth.user_group_mapping` | INSERT, DELETE | `group_mapping_created`, `group_mapping_deleted` |
| `triggers.notify_user_status` | `auth.user_info` | UPDATE, DELETE | `user_disabled`, `user_enabled`, `user_locked`, `user_unlocked`, `user_deleted` |
| `triggers.notify_owner` | `auth.owner` | INSERT, DELETE | `owner_created`, `owner_deleted` |
| `triggers.notify_provider` | `auth.provider` | UPDATE, DELETE | `provider_disabled`, `provider_enabled`, `provider_deleted` |
| `triggers.notify_perm_set` | `auth.perm_set` | UPDATE | `perm_set_updated` |
| `triggers.notify_permission` | `auth.permission` | UPDATE | `permission_assignability_changed` |
| `triggers.notify_tenant` | `auth.tenant` | DELETE | `tenant_deleted` |
| `triggers.notify_api_key` | `auth.api_key` | INSERT, DELETE | `api_key_created`, `api_key_deleted` |

**Backend Integration:**
```
1. Maintain a dedicated LISTEN connection (not from connection pool — PgBouncer transaction mode doesn't support LISTEN)
2. On notification: parse JSON, route by target_type (user/group/perm_set/tenant/provider/system)
3. Send SSE/WebSocket "REFETCH_PERMISSIONS" event to affected clients
4. Debounce: collect notifications for 100-200ms before broadcasting (bulk operations fire multiple triggers)
```

**Notification Resolution Views:**

Backend receives a notification with `target_type` + `target_id`, then queries the matching view to get affected user IDs:

| View | Query Pattern | Used For |
|------|--------------|----------|
| `auth.notify_group_users` | `WHERE user_group_id = $1` | `group_*` events, `permission_assigned` to group |
| `auth.notify_perm_set_users` | `WHERE perm_set_id = $1` | `perm_set_*` events |
| `auth.notify_permission_users` | `WHERE permission_id = $1` | `permission_assignability_changed` |
| `auth.notify_provider_users` | `WHERE provider_code = $1` | `provider_disabled`, `provider_deleted` |
| `auth.notify_tenant_users` | `WHERE tenant_id = $1` | `tenant_deleted` |
| *(no view needed)* | user_id is in the payload | `user_*`, `owner_*`, `group_member_*` events |

**Design Decisions:**
- Notifications are trigger-based (not embedded in `auth.*` functions) to preserve db-gen compatibility
- `auth.*` functions remain untouched — all new logic is in `triggers.*` and `unsecure.*` schemas
- Notifications are fire-and-forget (no persistence) — if nobody is listening, messages are discarded
- Cache invalidation is the correctness mechanism; notifications are an optimization for client freshness

**New File:** `033_triggers_cache_and_notify.sql`

### Fixed

#### Critical: Cache Invalidation Gaps
Multiple mutation points changed effective permissions but did NOT invalidate the permission cache, causing users to retain revoked permissions (or miss granted ones) for up to `perm_cache_timeout_in_s` seconds.

**Gaps fixed via trigger functions (in `triggers` schema):**

| Trigger Function | Table | Gap Fixed |
|-----------------|-------|-----------|
| `triggers.cache_user_group_member_delete` | `auth.user_group_member` AFTER DELETE | Removing user from group didn't clear cache — user retained group permissions |
| `triggers.cache_user_group_status_change` | `auth.user_group` AFTER UPDATE | Disabling/enabling a group didn't invalidate members' cache |
| `triggers.cache_user_group_before_delete` | `auth.user_group` BEFORE DELETE | Deleting a group cascade-deleted members but cached permissions persisted |
| `triggers.cache_provider_before_delete` | `auth.provider` BEFORE DELETE | Deleting provider cascade-deleted identities but cached permissions persisted |
| `triggers.cache_provider_status_change` | `auth.provider` AFTER UPDATE | Disabling provider didn't invalidate affected users' cache |

**Gaps fixed via direct changes in `unsecure.*` functions:**

| Function | Gap Fixed |
|----------|-----------|
| `unsecure.create_user_group_member()` | Adding user to group didn't clear cache — user didn't get group permissions until cache expired |
| `unsecure.set_permission_as_assignable()` | Making permission non-assignable didn't invalidate affected users — they kept the permission |
| `unsecure.update_perm_set()` | Changing perm_set `is_assignable` didn't invalidate affected users |

**Impact:** All permission-relevant mutations now take effect immediately instead of being delayed by cache timeout.

---

## [2.5.0] - 2026-02-14

### Added

#### User Events for Registration and Login
Added audit trail events for user registration and login flows:
- `user_registered` (10008) — new event code, fired on `auth.register_user` and `auth.ensure_user_from_provider` (new user)
- `user_logged_in` (10010) — fired on successful `auth.get_user_by_email_for_authentication` and `auth.ensure_user_from_provider` (returning user)
- `user_login_failed` (10012) — fired on all authentication failures (user not found, disabled, locked, identity disabled, login disabled)

Added `_ip_address`, `_user_agent`, `_origin` parameters to `auth.register_user`, `auth.get_user_by_email_for_authentication`, and `auth.ensure_user_from_provider` for client metadata in audit events.

### Changed

#### Code Generator Compatibility: Unique Journal Function Names
Split `public.create_journal_message` from 4 overloads sharing the same name into 4 distinctly named functions. PostgreSQL handles overloading natively, but external code generators (Elixir, C#) cannot distinguish functions that differ only by parameter types. Each overload now has a unique name that describes its purpose.

**Renamed functions:**

| Old Name (all `create_journal_message`) | New Name | Key Parameters | Usage |
|---|---|---|---|
| Overload 1 — event ID + keys | `create_journal_message` | `_event_id integer, _keys jsonb, _payload jsonb` | Unchanged — base function for arbitrary key journaling |
| Overload 2 — event code + keys | `create_journal_message_by_code` | `_event_code text, _keys jsonb, _payload jsonb` | Resolves event code to ID, then delegates to overload 1 |
| Overload 3 — entity shorthand | `create_journal_message_for_entity` | `_event_id integer, _entity_type text, _entity_id bigint` | Builds `{entity_type: entity_id}` keys automatically — most common pattern (~70+ call sites) |
| Overload 4 — entity + code | `create_journal_message_for_entity_by_code` | `_event_code text, _entity_type text, _entity_id bigint` | Resolves event code, then delegates to `_by_code` |

**Internal delegation chain:**
```
create_journal_message_for_entity_by_code → create_journal_message_by_code → create_journal_message
create_journal_message_for_entity → create_journal_message
```

**Callers updated across 15 files:**

| File | Calls | New Function |
|------|-------|-------------|
| `019_functions_unsecure.sql` | 22 | `create_journal_message_for_entity` |
| `021_functions_auth_group.sql` | 13 | `create_journal_message_for_entity` |
| `026_functions_auth_apikey.sql` | 10 | `create_journal_message_for_entity` |
| `020_functions_auth_user.sql` | 7 | `create_journal_message_for_entity` |
| `025_functions_auth_token.sql` | 7 | `create_journal_message_for_entity` |
| `024_functions_auth_provider.sql` | 5 | `create_journal_message_for_entity` |
| `023_functions_auth_tenant.sql` | 3 | `create_journal_message_for_entity` |
| `027_functions_auth_owner.sql` | 2 | `create_journal_message_for_entity` |
| `022_functions_auth_permission.sql` | 1 | `create_journal_message_for_entity` |
| `032_functions_translation.sql` | 2 | `create_journal_message_for_entity` |
| `018_functions_public.sql` | 1 | `create_journal_message_for_entity` |
| `031_functions_language.sql` | 3 | `create_journal_message` (unchanged — uses keys jsonb pattern) |
| `032_functions_translation.sql` | 2 | `create_journal_message` (unchanged — uses keys jsonb pattern) |
| `018_functions_public.sql` | 1 | `create_journal_message_by_code` |
| `tests/test_event_code_management.sql` | 1 | `create_journal_message_by_code` |
| `tests/test_correlation_id.sql` | 4 | `create_journal_message_for_entity` |

**Note:** `031_functions_language.sql` (3 calls) and `032_functions_translation.sql` (2 calls for `create_translation` and `copy_translations`) continue using `create_journal_message` — these calls pass `null::jsonb` as keys and a jsonb payload directly, matching overload 1's signature.

#### Code Generator Compatibility: Moved `throw_no_permission` to `internal` Schema
Moved all 4 overloads of `auth.throw_no_permission` → `internal.throw_no_permission`. This function is an internal helper used by `auth.has_permissions()` and a few other places to raise permission-denied exceptions. It was in the `auth` schema, which meant code generators would include it in auto-generated client code — but it should never be called directly from application code.

**Moved overloads:**

| Signature | Purpose |
|-----------|---------|
| `internal.throw_no_permission(_user_id bigint, _perm_codes text[], _tenant_id integer DEFAULT 1)` | Primary implementation — logs denial to journal, raises exception with all failed permission codes |
| `internal.throw_no_permission(_user_id bigint, _perm_codes text[])` | Convenience — delegates to primary with `_tenant_id := 1` |
| `internal.throw_no_permission(_user_id bigint, _perm_code text, _tenant_id integer DEFAULT 1)` | Single permission code — wraps into array, delegates to primary |
| `internal.throw_no_permission(_user_id bigint, _perm_code text)` | Single permission code — wraps into array, delegates to primary with `_tenant_id := 1` |

**Callers updated:**

| File | Context |
|------|---------|
| `022_functions_auth_permission.sql` | `has_permissions()` — calls `internal.throw_no_permission` on permission check failure |
| `018_functions_public.sql` | `search_journal()` — calls `internal.throw_no_permission` for global journal access check |
| `023_functions_auth_tenant.sql` | `assign_tenant_owner()` — calls `internal.throw_no_permission` for owner permission check |
| `999-examples.sql` | Updated examples |

**Impact:** The `internal` schema is excluded from code generation by convention (it contains business logic that's already permission-checked at a higher level). No behavior change at runtime — only the schema qualifier changes.

### Fixed

#### Bug: Email Registration Creates Inactive Identity
`auth.register_user()` called `unsecure.create_user_identity()` without passing `_is_active := true`,
so the identity defaulted to inactive. Login immediately failed with "identity disabled" error.
The provider-based flow (`auth.ensure_user_from_provider()`) was not affected.

#### Bug: Email Registration Stores Password Hash in Wrong Column
`auth.register_user()` passed `_password_hash` as the 7th positional argument to `unsecure.create_user_identity()`, which mapped to `_provider_oid` instead of `_password_hash`. Result: `password_hash` was null and `provider_oid` contained the hash — login always failed. Fixed by passing `lower(trim(_email))` as `_provider_oid` (7th arg) and the hash as `_password_hash` (8th arg).

---

## [2.4.0] - 2026-02-14

### Added

#### Hierarchical Short Permission Codes
Added compact hierarchical `short_code` to permissions for wire-format optimization. Instead of sending full permission codes like `token_configuration.create_token_type` (42 chars), services can download the mapping once at startup and send short codes like `05.01` over the wire.

**Schema Changes:**
- `auth.permission` - Added `short_code text` column with unique partial index
- `auth.user_permission_cache` - Added `short_code_permissions text[]` column

**New Functions:**

| Function | Description |
|----------|-------------|
| `unsecure.compute_short_code(_permission_id)` | Computes hierarchical short code (e.g., `03.01`) by counting sibling ordinals at each tree level |
| `unsecure.update_permission_short_code(_perm_path)` | Batch-updates short codes for all permissions in a subtree |
| `public.get_permissions_map()` | Returns `(permission_id, full_code, short_code, title)` for all assignable permissions - no permission check required |

**Optional Custom Short Code:** `unsecure.create_permission()`, `unsecure.create_permission_as_system()`, and `auth.create_permission()` accept an optional `_short_code text` parameter. When provided, the custom value is used instead of the auto-computed hierarchical code. This allows consumers to use custom codes (e.g., random tokens like `x7f9k2`) for specific permissions.

**Extended Return Types:**
- `unsecure.recalculate_user_permissions()` - Returns `__short_code_permissions text[]` as 5th column
- `auth.ensure_groups_and_permissions()` - Returns `__short_code_permissions text[]` as 5th column
- `auth.get_users_groups_and_permissions()` - Returns `__short_code_permissions text[]` as 5th column
- `auth.get_all_permissions()` - Returns `__short_code text` column
- `auth.search_permissions()` - Returns `__short_code text` column
- `unsecure.get_all_permissions()` - Returns `__short_code text` column
- `auth.effective_permissions` view - Added `permission_short_code` column

**Automatic Assignment:** `short_code` is computed automatically when permissions are created via `unsecure.create_permission()` (unless a custom `_short_code` is provided). Existing permissions are backfilled during seed data execution.

**Design:** Server-side `has_permissions()` checks remain text-based for readability/auditability. Short codes are purely for wire-format optimization in client-server communication.

#### Language & Translation System
Merged the standalone `postgresql-languages-model` into the permissions model. All functions now have direct access to a single language/translation system without duplicating infrastructure.

**New Tables:**

| Table | Description |
|-------|-------------|
| `const.language` | Language registry (PK: `code text`) with frontend/backend/communication flags, logical ordering, default flags, and custom_data jsonb |
| `public.translation` | Translation storage with full-text search (tsvector + gin_trgm_ops), supports both `data_object_code` (text key) and `data_object_id` (numeric key) lookups |

**New Language Functions (public schema):**

| Function | Permission | Description |
|----------|-----------|-------------|
| `create_language()` | `languages.create_language` | Create language, auto-unsets other defaults when setting `is_default_*=true` |
| `update_language()` | `languages.update_language` | Update language with same default enforcement |
| `delete_language()` | `languages.delete_language` | Delete language, CASCADE removes translations |
| `get_language()` | none | Get single language by code |
| `get_languages()` | none | Get all languages with optional frontend/backend/communication filters, LEFT JOIN translation for display name |
| `get_frontend_languages()` | none | Frontend languages ordered by `frontend_logical_order` |
| `get_backend_languages()` | none | Backend languages ordered by `backend_logical_order` |
| `get_communication_languages()` | none | Communication languages ordered by `communication_logical_order` |
| `get_default_language()` | none | Get default language for a category |

**New Translation Functions (public schema):**

| Function | Permission | Description |
|----------|-----------|-------------|
| `create_translation()` | `translations.create_translation` | Create translation, trigger auto-calculates search fields |
| `update_translation()` | `translations.update_translation` | Update translation value |
| `delete_translation()` | `translations.delete_translation` | Delete translation |
| `copy_translations()` | `translations.copy_translations` | Two-phase copy: update existing (if overwrite) then insert missing. Returns `(operation, count)` |
| `get_group_translations()` | none | Returns `jsonb_object_agg(data_object_code, value)` for a data_group |
| `search_translations()` | `translations.read_translations` | Paginated search with accent-insensitive matching via `normalize_text` |

**Trigger Infrastructure:**
- `helpers.calculate_ts_regconfig()` - Maps language code to PostgreSQL regconfig (en→english, de→german, fr→french, etc.)
- `triggers.calculate_translation_fields()` - BEFORE INSERT/UPDATE trigger auto-populates `ua_search_data` (normalized) and `ts_search_data` (tsvector)

**New Permissions:**

| Permission Code | Description |
|-----------------|-------------|
| `languages.create_language` | Create new languages |
| `languages.update_language` | Update existing languages |
| `languages.delete_language` | Delete languages |
| `languages.read_languages` | Read language list |
| `translations.create_translation` | Create translations |
| `translations.update_translation` | Update translations |
| `translations.delete_translation` | Delete translations |
| `translations.read_translations` | Search/read translations |
| `translations.copy_translations` | Copy translations between languages |

Added to `system_admin` and `tenant_admin` permission sets.

**New Event Codes:**

| Range | Category | Codes |
|-------|----------|-------|
| 17001-17999 | `language_event` | 17001 language_created, 17002 language_updated, 17003 language_deleted |
| 18001-18999 | `translation_event` | 18001-18003 CRUD, 18004 translations_copied |
| 35001-35999 | `language_error` | 35001 err_language_not_found, 35002 err_translation_not_found |

**New Error Functions:**
- `error.raise_35001(_language_code)` - Language not found
- `error.raise_35002(_translation_id)` - Translation not found

**FK Constraint:**
- `const.event_message.language_code` → `const.language.code` - Ensures event messages reference valid languages

**Seed Data:**
- Default 'en' (English) language with all flags set

**Design Decision:** `const.event_message` stays separate from `public.translation`. Event messages are templates with `{placeholder}` syntax and `is_active` versioning, tightly coupled to event codes. Translations are for plain UI text. Both share `const.language` as the language registry via FK.

**New Files:**

| File | Description |
|------|-------------|
| `030_tables_language.sql` | Tables, trigger, seed, FK, errors, events |
| `031_functions_language.sql` | 9 language functions |
| `032_functions_translation.sql` | 6 translation functions |
| `tests/test_language_translation.sql` | 25 test cases |

#### Test Runner Improvements
- Colored output in `tests/run-tests.sh`: green for PASS, red for FAIL/ERROR
- Colors auto-disable when output is piped (not a terminal)

#### Token Type CRUD Management
Runtime management of `const.token_type` entries, following the same pattern as event code CRUD.

**New Functions (public schema):**

| Function | Permission | Description |
|----------|-----------|-------------|
| `create_token_type()` | `token_configuration.create_token_type` | Create custom token type with optional expiration |
| `update_token_type()` | `token_configuration.update_token_type` | Update token type expiration (non-system only) |
| `delete_token_type()` | `token_configuration.delete_token_type` | Delete token type (non-system only) |
| `get_token_types()` | none | List all token types |

**Schema Changes:**
- Added `is_system boolean` column to `const.token_type` — protects seeded types from modification/deletion

**New Permissions:**

| Permission Code | Description |
|-----------------|-------------|
| `token_configuration.create_token_type` | Create new token types |
| `token_configuration.update_token_type` | Update existing token types |
| `token_configuration.delete_token_type` | Delete token types |
| `token_configuration.read_token_types` | Read token type list |

Added to `system_admin` permission set.

**New Event Codes:**

| Range | Category | Codes |
|-------|----------|-------|
| 19001-19999 | `token_config_event` | 19001 token_type_created, 19002 token_type_updated, 19003 token_type_deleted |
| 36001-36999 | `token_config_error` | 36001 err_token_type_not_found, 36002 err_token_type_is_system |

**New Error Functions:**
- `error.raise_36001(_token_type_code)` — Token type not found
- `error.raise_36002(_token_type_code)` — Token type is system

### Fixed

#### Bug: Missing `validation_failed` Token State
`auth.set_token_as_failed()` writes `'validation_failed'` to `token_state_code`, but seed data only included `'valid'`, `'used'`, `'expired'`, `'failed'`. This would cause an FK violation at runtime. Added `'validation_failed'` to `const.token_state` seed data.

#### Ambiguous Column References in Auth-Layer Functions
- `auth.can_manage_user_group` (`021_functions_auth_group.sql`) - Qualified `user_group_id` as `ug.user_group_id`; moved `ugm.user_id` filter from WHERE to JOIN ON so the LEFT JOIN works correctly (previously always returned no rows for non-members)
- `auth.get_user_available_tenants` (`023_functions_auth_tenant.sql`) - Qualified `tenant_id` and `user_group_id` with `ug.` prefix in CTE

#### Other Fixes
- `tests/test_event_code_management.sql` - TEST 18 now cleans up journal entries before deleting event code (FK constraint prevented deletion)

#### New Test Coverage
- `tests/test_auth_group_member_tenant.sql` - 11 tests for auth-layer group member & tenant functions (`auth.create_user_group_member`, `auth.delete_user_group_member`, `auth.get_user_group_members`, `auth.get_user_assigned_groups`, `auth.get_user_available_tenants`), covering happy paths, error cases (inactive/external/nonexistent groups), and full round-trip
- `tests/test_short_code.sql` - 16 tests for permission short codes: auto-computed hierarchical codes (format, depth, root vs child), custom `_short_code` parameter (override, pass-through via `create_permission_as_system`), unique constraint enforcement, schema validation (`effective_permissions` view, `user_permission_cache` column), return type verification (`get_permissions_map`, `get_all_permissions`), and `recalculate_user_permissions` cache population

### Changed
- **CLAUDE.md** - Added variable naming convention: `_` for parameters, `__` for return columns, `___` for local variables that clash with return columns

---

## [2.3.0] - 2026-02-12

### Added

#### Correlation ID Support for End-to-End Request Tracing
Added `_correlation_id text` parameter to all auth/public functions, enabling end-to-end request tracing from backend through the entire call chain down to audit tables.

**Schema changes:**
- Added `correlation_id text` column to `auth.user_event` table
- Added `correlation_id text` column to `public.journal` table
- Added partial indexes on both tables (`WHERE correlation_id IS NOT NULL`)

**New function:**
- `auth.search_user_events()` - Paginated search of user events with filters (correlation_id, event_type, target_user, date range)

**New permission:**
- `authentication.read_user_events` - Required for `auth.search_user_events()`

**Updated functions (~150 signatures):**
- All `auth.*` functions with `_user_id bigint` now accept `_correlation_id text` as the next parameter
- All `unsecure.*` functions forward `_correlation_id` to audit calls
- `auth.has_permission()` / `auth.has_permissions()` accept `_correlation_id` after `_target_user_id`
- `create_journal_message()` overloads forward `_correlation_id` to journal INSERT
- `search_journal()` / `search_journal_msgs()` support filtering by `_correlation_id`

**Call chain flow:**
```
Backend (generates correlation_id)
  → auth.*(... _correlation_id ...)
    → auth.has_permission(... _correlation_id ...) → journal on denial
    → unsecure.*(... _correlation_id ...)
      → create_journal_message(... _correlation_id ...) → public.journal
      → unsecure.create_user_event(... _correlation_id ...) → auth.user_event
```

**Files modified:** 018, 019, 020, 021, 022, 023, 024, 025, 026, 027, 028 (function files), 013, 014 (table files)

---

## [2.2.0] - 2026-02-11

### Fixed

#### Critical: Cache Invalidation on Permission Changes
Permission cache is now properly invalidated when permissions are assigned, unassigned, or when permission set contents change:

- `unsecure.assign_permission()` - Now clears cache for affected user or group members
- `unsecure.unassign_permission()` - Now clears cache for affected user or group members
- `unsecure.add_perm_set_permissions()` - Now clears cache for all users with this perm_set
- `unsecure.delete_perm_set_permissions()` - Now clears cache for all users with this perm_set

**Impact:** Users now see permission changes immediately instead of waiting 15-300 seconds for cache expiry.

### Changed

#### Soft Invalidation Strategy for Group/PermSet Operations
For large-scale cache invalidation (groups and permission sets), the system now uses "soft invalidation" instead of DELETE:

```sql
-- Before: Hard DELETE (caused index rebalancing, slow for large datasets)
DELETE FROM auth.user_permission_cache WHERE user_id IN (SELECT ...);

-- After: Soft invalidation (UPDATE expiration_date, ~5-10x faster)
UPDATE auth.user_permission_cache
SET expiration_date = now(), updated_by = _deleted_by, updated_at = now()
WHERE user_id IN (SELECT ...);
```

**Functions using soft invalidation:**
- `unsecure.invalidate_group_members_permission_cache()` - For group membership changes
- `unsecure.invalidate_perm_set_users_permission_cache()` - For permission set changes

**Why this works:** `has_permissions()` checks `expiration_date > now()` before using cache. If expired, it calls `recalculate_user_permissions()`. The next permission check triggers immediate recalculation.

**Benefits:**
- ~5-10x faster than DELETE (no index rebalancing)
- No transaction blocking from mass row deletions
- Cache rows ready for reuse (no INSERT overhead on recalc)
- Scales well for large deployments (100+ groups × 1000+ members)

**Individual user cache** (`clear_permission_cache`) still uses DELETE since it only affects one user's rows where the performance difference is negligible.

#### Disabled/Locked Users Now Blocked from Permission Checks
- `unsecure.recalculate_user_permissions()` now validates user is active and not locked
- `auth.disable_user()` and `auth.lock_user()` now clear permission cache for all tenants
- Previously, disabled/locked users could still pass permission checks until cache expired

**Impact:** Disabled or locked users are immediately blocked from all permission-protected operations.

### Added

#### Outbound API Key Support
New capability to store credentials for calling external services (SendGrid, Slack, Azure, etc.):

**Table Changes (`auth.api_key`):**
| Column | Type | Description |
|--------|------|-------------|
| `key_type` | text | `'inbound'` (default) or `'outbound'` |
| `encrypted_secret` | bytea | Pre-encrypted secret (application-side encryption) |
| `service_code` | text | Service identifier (e.g., `'sendgrid'`, `'slack'`) |
| `service_url` | text | Service endpoint URL |
| `extra_data` | jsonb | Extra headers, config, etc. |

**Security Model:**
- Encryption/decryption handled by application layer
- Database stores pre-encrypted `bytea` data (no pg_crypto required)
- Separate permission `api_keys.read_outbound_secret` for retrieving secrets

**New Functions:**
| Function | Description |
|----------|-------------|
| `auth.create_outbound_api_key` | Create outbound key with encrypted secret |
| `auth.get_outbound_api_key` | Get outbound key by service code |
| `auth.get_outbound_api_key_by_id` | Get outbound key by ID |
| `auth.get_outbound_api_key_secret` | Retrieve encrypted secret (requires special permission) |
| `auth.get_outbound_api_key_secret_by_id` | Retrieve encrypted secret by ID |
| `auth.update_outbound_api_key` | Update metadata (not secret) |
| `auth.update_outbound_api_key_secret` | Rotate encrypted secret |
| `auth.search_outbound_api_keys` | Search outbound keys |
| `auth.delete_outbound_api_key` | Delete outbound key |

**Example Usage:**
```sql
-- Create outbound key (app encrypts 'my-sendgrid-key' → bytea)
SELECT auth.create_outbound_api_key(
    'admin', 1, 'SendGrid API', 'Email service',
    _service_code := 'sendgrid',
    _encrypted_secret := '\x...'::bytea,  -- Pre-encrypted by app
    _service_url := 'https://api.sendgrid.com',
    _extra_data := '{"headers": {"X-Custom": "value"}}'::jsonb,
    _tenant_id := 1
);

-- Retrieve encrypted secret (app decrypts result)
SELECT auth.get_outbound_api_key_secret('admin', 1, 'sendgrid', 1);
```

#### New Helper Functions
| Function | Description |
|----------|-------------|
| `unsecure.invalidate_group_members_permission_cache` | Invalidates permission cache for all members of a group |
| `unsecure.invalidate_perm_set_users_permission_cache` | Invalidates permission cache for all users with a specific perm_set |
| `unsecure.verify_owner_or_permission` | Validates user is owner or has appropriate permission (consolidates duplicate code) |
| `error.raise_33004(bigint)` | Overload for locked user error that accepts user_id instead of email |

#### New Permissions
| Permission Code | Description |
|-----------------|-------------|
| `api_keys.read_outbound_secret` | Required to retrieve encrypted secrets for outbound API keys |

### Changed

#### Enhanced clear_permission_cache
- `unsecure.clear_permission_cache()` now accepts NULL for `_tenant_id` parameter
- When NULL, clears cache for ALL tenants (used when user is locked/disabled)
- Default changed from 1 to NULL for broader utility

#### Parameter Validation in assign_permission
- `unsecure.assign_permission()` now throws error `22023` (invalid_parameter_value) if both `_user_group_id` AND `_target_user_id` are provided
- Previously the function silently used whichever parameter was non-null first, which was ambiguous

#### Provider Validation in recalculate_user_groups
- `unsecure.recalculate_user_groups()` now validates that `_provider_code` exists before proceeding
- Previously a non-existent provider code would silently result in NULL arrays, which would incorrectly clear all external group memberships

#### Refactored Owner Functions
- `auth.create_owner()` and `auth.delete_owner()` now use `unsecure.verify_owner_or_permission()` helper
- Eliminates code duplication between these functions

---

## [2.1.0] - 2026-02-11

### Added

#### Search/Paging Functions
New search functions with offset-based pagination for all auth entities:

| Function | Description |
|----------|-------------|
| `auth.search_users` | Search users with filters for user_type, is_active, is_locked |
| `auth.search_user_groups` | Search groups with member counts |
| `auth.search_tenants` | Search tenants |
| `auth.search_permissions` | Search permissions with parent_code filtering |
| `auth.search_perm_sets` | Search permission sets with permission counts |

All search functions support:
- Text search on `nrm_search_data` column using LIKE pattern matching
- Pagination via `_page` and `_page_size` parameters
- `total_items` count via window function

#### New Group Function
- `auth.set_user_group_as_internal` - Convert hybrid/external group back to internal-only (complement to `set_user_group_as_external` and `set_user_group_as_hybrid`)

#### New Permissions
| Permission Code | Description |
|-----------------|-------------|
| `users.read_users` | Required for `search_users` |
| `tenants.read_tenants` | Required for `search_tenants` |
| `tenants.delete_tenant` | Required for tenant deletion |
| `permissions.read_permissions` | Required for `search_permissions` |
| `permissions.read_perm_sets` | Required for `search_perm_sets` |

#### Schema Updates
Added `nrm_search_data` columns with GIN indexes for trigram search to:
- `auth.tenant`
- `auth.user_group`
- `auth.permission`
- `auth.perm_set`
- `auth.api_key`

Added trigger functions in `017_functions_triggers.sql` to auto-populate search data on INSERT/UPDATE.

### Changed

#### Parameter Naming Fix
- `auth.delete_user_group_mapping`: renamed `_ug_mapping_id` → `_user_group_mapping_id` for consistency

---

## [2.0.0] - 2026-02-10

### Breaking Changes

#### Removed Template Table Inheritance
- **Removed** `public._template_created` and `public._template_timestamps` template tables
- **Removed** PostgreSQL table inheritance (`INHERITS` clause) from all tables
- Tables now have explicit `created_at`, `created_by`, `updated_at`, `updated_by` columns
- **Reason**: PostgreSQL table inheritance caused slow DELETE operations due to engine scanning all child tables

#### Column Renames
- `created` → `created_at` (timestamp column, for clarity)
- `modified` → `updated_at` (timestamp column, consistent naming)
- `modified_by` → `updated_by` (text column, consistent naming)
- `created_by` remains unchanged

#### Journal Table Restructure
- **Removed** columns: `message`, `nrm_search_data`, `data_group`, `data_object_id`, `data_object_code`
- **Added** `keys` JSONB column for multi-key support
- **Added** `data_payload` JSONB column for template values and extra data
- **Added** foreign key from `event_id` to `const.event_code`
- **Added** `primary key` constraint to `journal_id`

Messages are no longer stored directly - they're resolved at display time from templates:
```sql
-- Store entry with template values
INSERT INTO journal (tenant_id, event_id, keys, data_payload)
VALUES (1, 10001, '{"user": 123}', '{"username": "john", "actor": "admin"}');

-- Query by any key
SELECT * FROM journal WHERE keys @> '{"user": 123}';

-- Message resolved at display time:
-- Template: 'User "{username}" was created by {actor}'
-- Result:   'User "john" was created by admin'
```

#### Message Template System
- **Added** `const.event_message` table for i18n message templates
- Messages use `{placeholder}` syntax filled from `data_payload` at display time
- Supports multiple languages per event code
- Eliminates redundant storage of identical messages

#### New Journal Functions
Replaced `add_journal_msg` with new `create_journal_message` functions (no `_msg` parameter - messages come from templates):

```sql
-- Option 1: Using event_id with keys and payload
SELECT * FROM create_journal_message(
    'admin',                                    -- created_by
    1,                                          -- user_id
    10001,                                      -- event_id (user_created)
    '{"user": 123}'::jsonb,                     -- keys
    '{"username": "john", "actor": "admin"}'::jsonb,  -- payload for template
    1                                           -- tenant_id
);

-- Option 2: Using event code string
SELECT * FROM create_journal_message(
    'admin', 1, 'user_created',
    _keys := '{"user": 123}'::jsonb,
    _payload := '{"username": "john"}'::jsonb
);

-- Option 3: Single entity convenience
SELECT * FROM create_journal_message(
    'admin', 1, 'group_created',
    'group', 456,  -- entity_type, entity_id -> keys: {"group": 456}
    '{"group_title": "Admins"}'::jsonb
);

-- Search by event category (for UI filtering)
SELECT * FROM search_journal(
    _user_id := 1,
    _event_category := 'user_event',
    _keys_criteria := '{"user": 123}'::jsonb
);

-- Get entry with resolved message
SELECT * FROM get_journal_entry(1, 1, 123);
-- Returns __message: 'User "john" was created by admin'
```

**New functions:**
- `create_journal_message()` - Core function with multiple overloads (no message param)
- `journal_keys()` - Helper to build keys JSONB from variadic pairs
- `format_journal_message()` - Resolve template placeholders from payload
- `get_event_message_template()` - Get template for event in specified language
- `search_journal()` - Search with event category support, returns resolved messages
- `get_journal_entry()` - Get single entry with resolved message

**Legacy compatibility:** `add_journal_msg` and `add_journal_msg_jsonb` still work as wrappers.

#### New Event/Error Code Ranges
Old 50xxx/52xxx codes have been reorganized into clear ranges:

| Range | Category | Description |
|-------|----------|-------------|
| 10001-10999 | User Events | Login, logout, password change, identity management |
| 11001-11999 | Tenant Events | Created, updated, deleted, user access changes |
| 12001-12999 | Permission Events | Assigned, revoked, permission set management |
| 13001-13999 | Group Events | Member added/removed, mapping changes |
| 14001-14999 | API Key Events | Created, updated, deleted, validation |
| 15001-15999 | Token Events | Created, used, expired, failed |
| 30001-30999 | Security Errors | API key/token validation failures |
| 31001-31999 | Validation Errors | Missing required parameters |
| 32001-32999 | Permission Errors | Permission not found, not assignable |
| 33001-33999 | User/Group Errors | User/group not found, not active, system entity |
| 34001-34999 | Tenant Errors | No tenant access |
| 50000+ | Reserved | Application-specific events and errors |

**Backwards Compatibility**: Old `error.raise_52xxx()` functions are preserved as aliases to new `error.raise_3xxxx()` functions.

### Added

#### New Event Code Tables
- `const.event_category` - Event category definitions with ranges
- `const.event_code` - Individual event/error code definitions
- `const.event_message` - Message templates per event_id and language_code

#### New Error Functions (30xxx series)
Security/Auth Errors:
- `error.raise_30001` - API key/secret invalid
- `error.raise_30002` - Token invalid or expired
- `error.raise_30003` - Token belongs to different user
- `error.raise_30004` - Token already used
- `error.raise_30005` - Token not found

Validation Errors:
- `error.raise_31001` - Either group or user required
- `error.raise_31002` - Either perm set or permission required
- `error.raise_31003` - Either permission id or code required
- `error.raise_31004` - Either mapping id or role required

Permission Errors:
- `error.raise_32001` - No permission
- `error.raise_32002` - Permission not found
- `error.raise_32003` - Permission not assignable
- `error.raise_32004` - Permission set not found
- `error.raise_32005` - Permission set not assignable
- `error.raise_32006` - Permission set wrong tenant
- `error.raise_32007` - Parent permission not found
- `error.raise_32008` - Some permissions not assignable

User/Group Errors:
- `error.raise_33001` - User not found
- `error.raise_33002` - User is system
- `error.raise_33003` - User not active
- `error.raise_33004` - User locked
- `error.raise_33005` - User cannot login
- `error.raise_33006` - User no email provider
- `error.raise_33007` - Identity already used
- `error.raise_33008` - Identity not active
- `error.raise_33009` - Identity not found
- `error.raise_33010` - Provider not active
- `error.raise_33011` - Group not found
- `error.raise_33012` - Group not active
- `error.raise_33013` - Group not assignable
- `error.raise_33014` - Group is system
- `error.raise_33015` - Not owner

Tenant Errors:
- `error.raise_34001` - No tenant access

### Changed

#### File Structure Reorganization
Consolidated migration files into modular structure:

| File | Contents |
|------|----------|
| `001_create_basic_structure.sql` | Schemas and extensions |
| `002_create_version_management.sql` | Version tracking system |
| `004_create_helpers.sql` | Helper functions |
| `005-009_update_common-helpers_v1-x.sql` | Helper updates |
| `010_functions_auth_prereq.sql` | Auth prerequisite functions |
| `012_tables_const.sql` | Constant/lookup tables |
| `013_tables_auth.sql` | Auth schema tables |
| `014_tables_stage.sql` | Stage tables and journal |
| `015_views.sql` | Database views |
| `016_functions_error.sql` | Error functions |
| `017_functions_triggers.sql` | Trigger functions |
| `018_functions_public.sql` | Public schema functions |
| `019_functions_unsecure.sql` | Unsecure schema functions |
| `020-028_functions_auth_*.sql` | Auth schema functions |
| `029_seed_data.sql` | Initial data inserts |
| `099_fix_permissions.sql` | Permission grants |

#### Schema Resolution
- All SQL files now include `set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;`
- Enables each file to be executed independently by debee
- Removes need for `ext.` prefix on ltree, uuid_generate_v4(), etc.

### Fixed

- **tenant uuid unique index** - Moved to immediately after tenant table creation (before user_permission_cache references it)
- **Journal table dependencies** - Moved journal table to after auth tables are created
- **COST 0 error** - Changed `cost 0` to `cost 1` in helper functions (COST must be positive)

### Migration Guide

#### From v1.x to v2.0

1. **Database Recreation Required**: v2 is not an incremental update. Backup data and recreate:
   ```powershell
   ./debee.ps1 -Operations fullService
   ```

2. **Error Code Updates** (if using directly):
   - Old: `error.raise_52103(_user_id)`
   - New: `error.raise_33001(_user_id, _email)`
   - Aliases are provided for backwards compatibility

3. **Event Code Updates** (if querying journal):
   - Old event codes (50xxx) mapped to new codes (10xxx)
   - Query `const.event_code` for new event definitions

4. **Column Renames** (if accessing tables directly):
   - `created` → `created_at`
   - `modified` → `updated_at`
   - `modified_by` → `updated_by`
   - `created_by` remains unchanged

5. **Journal Function Updates**:
   - Old: `add_journal_msg(_created_by, _user_id, _msg, 'group', 123, _event_id := 50123)`
   - New: `create_journal_message(_created_by, _user_id, 13001, 'group', 123, '{"group_title": "Admins"}'::jsonb)`
   - Messages no longer stored - resolved from `const.event_message` templates at display time
   - Legacy `add_journal_msg` functions still work (message stored in `data_payload._legacy_msg`)

---

## [1.16] - Previous Release

See git history for v1.x changes.

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 2.16.0 | 2026-03-02 | Bulk ensure functions for app bootstrapping, `_is_final_state` declarative sync, `source` column on user_group |
| 2.15.0 | 2026-03-01 | Event ID collision fix, column renames, Makefile debee migration |
| 2.14.0 | 2026-02-28 | Resource access (ACL) system, provider capability flags |
| 2.13.0 | 2026-02-28 | User group caching, hierarchical resource access |
| 2.12.0 | 2026-02-26 | Search function fixes, group member tenant functions |
| 2.11.0 | 2026-02-26 | Event code management, audit partitioning, storage modes |
| 2.10.0 | 2026-02-23 | Request context tracking, user events for registration/login |
| 2.9.0 | 2026-02-22 | User event system, registration/login bug fixes |
| 2.8.0 | 2026-02-21 | Audit infrastructure, composable admin permission sets, ensure_provider, bug fixes |
| 2.7.0 | 2026-02-21 | Dedicated service accounts with least-privilege permissions, missing permission seed fixes |
| 2.6.0 | 2026-02-20 | Real-time LISTEN/NOTIFY notifications, cache invalidation gap fixes |
| 2.5.0 | 2026-02-14 | Code generator compatibility: unique journal function names, throw_no_permission moved to internal |
| 2.4.0 | 2026-02-14 | Hierarchical numeric permission codes, language & translation system, colored test output |
| 2.3.0 | 2026-02-12 | Correlation ID tracing, consolidate seed data |
| 2.2.0 | 2026-02-11 | Cache invalidation fixes, soft invalidation strategy, parameter validation |
| 2.1.0 | 2026-02-11 | Search/paging functions, set_user_group_as_internal |
| 2.0.0 | 2026-02-10 | Major restructure: removed inheritance, new event codes |
| 1.16 | - | API key tenant_id fix |
| 1.0-1.15 | - | Incremental feature additions |
