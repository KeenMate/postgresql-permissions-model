# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
| 2.5.0 | 2026-02-14 | Code generator compatibility: unique journal function names, throw_no_permission moved to internal |
| 2.4.0 | 2026-02-14 | Hierarchical numeric permission codes, language & translation system, colored test output |
| 2.3.0 | 2026-02-12 | Correlation ID tracing, consolidate seed data |
| 2.2.0 | 2026-02-11 | Cache invalidation fixes, soft invalidation strategy, parameter validation |
| 2.1.0 | 2026-02-11 | Search/paging functions, set_user_group_as_internal |
| 2.0.0 | 2026-02-10 | Major restructure: removed inheritance, new event codes |
| 1.16 | - | API key tenant_id fix |
| 1.0-1.15 | - | Incremental feature additions |
