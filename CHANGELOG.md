# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `const.user_event_type.event_id` - Links legacy event types to new event codes

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
   - Old event codes (50xxx) mapped to new codes (10xxx) via `const.user_event_type.event_id`
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
| 2.0.0 | 2026-02-10 | Major restructure: removed inheritance, new event codes |
| 1.16 | - | API key tenant_id fix |
| 1.0-1.15 | - | Incremental feature additions |
