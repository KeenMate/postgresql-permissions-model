# PostgreSQL Permissions Model v2 Planning

## Overview

This document tracks all breaking changes and improvements planned for v2. The goal is to consolidate all migration scripts (001-027) into a single clean schema file with architectural fixes.

## Migration Strategy

1. Run v1 migrations to get complete database
2. Export schema from DataGrip
3. Apply v2 changes to exported schema
4. Replace migration files with single `001_create_permissions.sql`

---

## Issues & Proposals

### A) Template Tables (Inheritance)

**Status:** ✅ COMPLETED (2026-02-10)

Removed PostgreSQL table inheritance. All tables now have explicit columns:
```sql
created_at  timestamptz not null default now(),
created_by  text not null default 'unknown',
updated_at  timestamptz not null default now(),
updated_by  text not null default 'unknown'
```

**Files changed:** `012_tables_const.sql`, `013_tables_auth.sql`, `014_tables_stage.sql`

---

### B) Naming: Consistent Timestamp Columns

**Status:** ✅ COMPLETED (2026-02-10)

Renamed columns for clarity and consistency:
```sql
-- Old (v1)           -- New (v2)
created            -> created_at
created_by         -> created_by (unchanged)
modified           -> updated_at
modified_by        -> updated_by
```

**Files changed:** All table definitions and functions referencing these columns

---

### C) Event/Error Code Separation

**Status:** ✅ COMPLETED (2026-02-10)

Implemented clear code ranges:
```
10000-19999  Informational events (user, tenant, permission, group, apikey, token)
30000-39999  Errors (security, validation, permission, user/group, tenant)
50000+       Reserved for applications
```

**Added:**
- `const.event_category` - Category definitions with ranges
- `const.event_code` - Individual event/error code definitions
- `const.user_event_type.event_id` - Links legacy event types to new codes
- Backwards compatibility aliases (52xxx → 3xxxx)

**Files changed:** `012_tables_const.sql`, `016_functions_error.sql`, `029_seed_data.sql`

---

### D) Journal Multi-Key Support + Message Templates

**Status:** ✅ COMPLETED (2026-02-11)

Restructured journal table - messages resolved from templates, not stored:
```sql
create table journal (
    created_at   timestamptz not null default now(),
    created_by   text not null default 'unknown',
    journal_id   bigint generated always as identity primary key,
    tenant_id    int references auth.tenant,
    event_id     int references const.event_code,
    user_id      bigint references auth.user_info,
    keys         jsonb,        -- {"order": 3, "item": 5}
    data_payload jsonb         -- {"username": "john", "actor": "admin"}
);

-- GIN indexes for efficient @> queries
create index ix_journal_keys on journal using gin(keys);
create index ix_journal_payload on journal using gin(data_payload);
```

**Message Template System:**
```sql
-- Templates stored in const.event_message
-- Template: 'User "{username}" was created by {actor}'
-- + payload: {"username": "john", "actor": "admin"}
-- = Display: 'User "john" was created by admin'

-- Functions
SELECT get_event_message_template(10001);           -- Get template
SELECT format_journal_message(template, payload);   -- Resolve placeholders
SELECT * FROM get_journal_entry(1, 1, 123);         -- Returns resolved message
```

**Changes:**
- Removed columns: `message`, `nrm_search_data`, `data_group`, `data_object_id`, `data_object_code`
- Added `keys` JSONB column with GIN index
- Added `data_payload` JSONB column for template values
- Added `const.event_message` table for i18n message templates
- Messages resolved at display time (not stored)
- Legacy `add_journal_msg` functions work via wrappers

**Files changed:** `014_tables_stage.sql`, `012_tables_const.sql`, `018_functions_public.sql`, `029_seed_data.sql`

---

### E) Additional Items (To Be Detailed)

| # | Issue | Notes | Priority |
|---|-------|-------|----------|
| E1 | Remove unused functions | Audit db-objects.md for dead code | Medium |
| E2 | Consistent parameter naming | `_user_id` vs `_target_user_id` patterns | Low |
| E3 | Permission cache improvements | Current expiration logic? | Medium |
| E4 | API key tenant_id fix | Already fixed in v1.16, verify in v2 | Done |
| E5 | Function schema consistency | When to use auth vs internal vs unsecure | High |
| E6 | Error message improvements | More context in error.raise_* functions | Low |
| E7 | | | |
| E8 | | | |

---

## Files to Change

After DataGrip export, these structural changes apply:

```
REMOVE:
  007_update_permissions_v1-1.sql
  008_update_permissions_v1-2.sql
  ... (all 007-027 files)

KEEP AS-IS:
  000_create_database.sql
  002_create_version_management.sql (separate package)
  99_fix_permissions.sql

CONSOLIDATE INTO:
  001_create_basic_structure.sql (schemas, extensions)
  003_create_helpers.sql (utility functions)
  004_create_permissions.sql (main system - CLEAN VERSION)
```

---

## Version Management

v2 should start fresh version tracking:

```sql
select * from start_version_update('2.0',
    'PostgreSQL Permissions Model v2 - Clean architecture',
    _description := 'Consolidated schema with: direct columns (no inheritance), updated->updated_by naming, separated event/error codes, multi-key journal',
    _component := 'postgresql_permissionmodel');
```

---

## Testing Checklist

Before releasing v2:

- [x] All auth.* functions work with new column names
- [x] Permission checks still work correctly
- [x] Journal entries can store multiple keys
- [x] Event codes properly categorized
- [x] DELETE performance improved (no inheritance)
- [x] Existing applications can migrate (see CHANGELOG.md)
- [x] Message templates resolve correctly from event_message
- [x] Legacy add_journal_msg wrappers work
- [x] search_journal returns resolved messages
- [x] get_journal_entry returns resolved messages

---

## Open Questions

1. Should v2 provide a migration script from v1 databases?
2. Keep `002_create_version_management.sql` or make it optional?
3. Default tenant_id: keep `1` or make it configurable?
4. Should we add soft-delete support (`deleted_at` column)?

---

*Last updated: 2026-02-11*
