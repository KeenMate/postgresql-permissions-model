# PostgreSQL Permissions Model

A comprehensive PostgreSQL database model for multi-tenant user/group/permissions management with hierarchical permissions, permission sets, and flexible identity provider integration.

## Overview

This is a standalone PostgreSQL framework that provides complete tenant/user/group/permissions management for any PostgreSQL project. It's production-ready and used in many real-world projects, both big and small.

## Key Features

- **Multi-tenancy** with isolated permissions and data
- **Hierarchical permissions** using PostgreSQL ltree (e.g., `users.create_user.admin_level`)
- **Flexible group types**: Internal, External (mapped to identity providers), and Hybrid
- **Identity provider integration**: Works with any provider (Windows Auth, AzureAD, Google, Facebook, KeyCloak, LDAP, etc.)
- **Permission sets** for role-based access control
- **API key management** with technical user pattern
- **Comprehensive audit logging** with multi-key journal entries and event categories
- **Permission caching** for performance
- **Built-in search/paging** for users, groups, tenants, permissions, and permission sets

## Quick Start

### Setup
```powershell
# Full database setup (recreate, restore, and update)
./debee.ps1 -Operations fullService

# Or individual operations
./debee.ps1 -Operations recreateDatabase
./debee.ps1 -Operations updateDatabase
```

### Configuration
Configure connection in `debee.env`:
```
PGHOST=localhost
PGPORT=5432
PGUSER=postgres
PGPASSWORD=your_password
DBDESTDB=your_database_name
```

### Running SQL
Use `exec-sql.sh` for quick SQL execution:
```bash
./exec-sql.sh "SELECT * FROM auth.user_info;"   # Inline SQL
./exec-sql.sh -f script.sql                      # Run file
./exec-sql.sh                                    # Interactive psql
```

### Basic Usage
```sql
-- Check user permission (throws exception if denied)
perform auth.has_permission(_tenant_id, _user_id, 'orders.cancel_order');

-- Silent permission check
if auth.has_permission(_tenant_id, _user_id, 'orders.view', _throw_err := false) then
    -- user has permission
end if;

-- Create permission
select auth.create_permission_by_path('orders.cancel_order', 'Cancel Order');

-- Assign permission to user
select auth.assign_permission(_created_by, _user_id, _tenant_id, _target_user_id, null, 'orders.cancel_order');

-- Search users with pagination
select * from auth.search_users(
    _user_id := 1,
    _search_text := 'john',
    _is_active := true,
    _page := 1,
    _page_size := 20,
    _tenant_id := 1
);

-- Search groups with member counts
select * from auth.search_user_groups(1, 'admin', _is_active := true);

-- Search permissions by parent
select * from auth.search_permissions(1, null, _parent_code := 'users');
```

## Architecture

### Core Components
- **`auth.user_info`** - Core user data
- **`auth.user_identity`** - Multiple identity provider support per user
- **`auth.user_data`** - Extensible custom user fields
- **`auth.tenant`** - Multi-tenancy management
- **`auth.user_group`** - Three group types (internal/external/hybrid)
- **`auth.permission`** - Global hierarchical permissions
- **`auth.perm_set`** - Tenant-specific permission collections
- **`auth.api_key`** - Service authentication with technical users
- **`public.journal`** - Audit logging with multi-key support

### Schema Security Model
- **`public`** & **`auth`** - Always validate permissions
- **`internal`** - For trusted contexts (no permission checks)
- **`unsecure`** - Security system internals only

## Journal / Audit Logging

The `public.journal` table provides comprehensive audit logging with multi-key support.

### Creating Journal Entries

```sql
-- Using event code name (recommended)
SELECT * FROM create_journal_message(
    'admin',           -- created_by
    1,                 -- user_id
    'user_created',    -- event code (text)
    'New user registered',
    _keys := '{"user": 123, "tenant": 1}'::jsonb
);

-- Single entity convenience
SELECT * FROM create_journal_message(
    'admin', 1, 'group_created', 'Group created',
    'group', 456  -- entity_type, entity_id
);

-- Using helper for multiple keys
SELECT * FROM create_journal_message(
    'admin', 1, 'permission_assigned', 'Permission granted',
    _keys := journal_keys('user', '123', 'group', '456', 'permission', '789')
);
```

### Searching Journal

```sql
-- Search by event category (for UI filtering like "show all user events")
SELECT * FROM search_journal(
    _user_id := 1,
    _event_category := 'user_event'
);

-- Search by entity keys
SELECT * FROM search_journal(
    _user_id := 1,
    _keys_criteria := '{"order": 3}'::jsonb
);

-- Full-text search with filters
SELECT * FROM search_journal(
    _user_id := 1,
    _search_text := 'password',
    _event_category := 'user_event',
    _from := now() - interval '7 days'
);
```

### Event Categories

| Category | Description |
|----------|-------------|
| `user_event` | User lifecycle, login, password changes |
| `tenant_event` | Tenant management |
| `permission_event` | Permission assignments |
| `group_event` | Group membership changes |
| `apikey_event` | API key operations |
| `token_event` | Token lifecycle |

## Group Mapping Strategy

Supports three group types for flexible identity provider integration:

- **Internal Groups**: Traditional membership stored in database
- **External Groups**: Membership determined by identity provider mappings (no local storage)
- **Hybrid Groups**: Combination of both approaches

Example: User logs in with AzureAD groups → System maps external groups to internal permissions → User gets permissions without being explicitly added as member.

## Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Developer guide for Claude Code
- **Complete Documentation** - [postgresql-permissions-model-docs](../postgresql-permissions-model-docs) (comprehensive documentation project)
- **[functions.md](./functions.md)** - Function reference
- **[features.md](./features.md)** - Feature list

## Integration

### With Application Libraries
The separate `keen-auth-permissions` library provides application-level wrappers around these SQL functions.

### Direct SQL Integration
Always use fully qualified schema names to avoid search_path issues:
```sql
-- Good
select auth.has_permission(_tenant_id, _user_id, 'permission.code');

-- Avoid (can cause "cannot find function" errors)
select has_permission(_tenant_id, _user_id, 'permission.code');
```

## Version Management

Simple version tracking with `public.__version` table:
```sql
select * from public.start_version_update('1.0', 'Initial version');
-- migration content
select * from public.stop_version_update('1.0');
```

## Requirements

- PostgreSQL with extensions: `ltree`, `uuid-ossp`, `unaccent`, `pg_trgm`
- PowerShell (for setup scripts)

## License

[MIT License](./LICENSE)

## Event and Error Codes

The system uses structured event/error codes organized by category. Codes are stored in `const.event_code` table.

### Code Ranges

| Range | Category | Description |
|-------|----------|-------------|
| 10001-10999 | User Events | Login, logout, password, identity management |
| 11001-11999 | Tenant Events | Tenant lifecycle and user access |
| 12001-12999 | Permission Events | Permission and permission set management |
| 13001-13999 | Group Events | Group membership and mappings |
| 14001-14999 | API Key Events | API key lifecycle and validation |
| 15001-15999 | Token Events | Token lifecycle |
| 30001-30999 | Security Errors | Authentication and token errors |
| 31001-31999 | Validation Errors | Missing required parameters |
| 32001-32999 | Permission Errors | Permission not found, not assignable |
| 33001-33999 | User/Group Errors | Entity not found, not active, system entity |
| 34001-34999 | Tenant Errors | Tenant access errors |
| 50000+ | Reserved | Application-specific events and errors |

### Informational Events (10xxx-15xxx)

#### User Events (10001-10999)

| Code | Event | Description |
|------|-------|-------------|
| 10001 | user_created | New user account was created |
| 10002 | user_updated | User account was updated |
| 10003 | user_deleted | User account was deleted |
| 10004 | user_enabled | User account was enabled |
| 10005 | user_disabled | User account was disabled |
| 10006 | user_locked | User account was locked |
| 10007 | user_unlocked | User account was unlocked |
| 10010 | user_logged_in | User successfully logged in |
| 10011 | user_logged_out | User logged out |
| 10012 | user_login_failed | User login attempt failed |
| 10020 | password_changed | User password was changed |
| 10021 | password_reset_requested | Password reset was requested |
| 10022 | password_reset_completed | Password reset was completed |
| 10030 | identity_created | User identity was created |
| 10031 | identity_updated | User identity was updated |
| 10032 | identity_deleted | User identity was deleted |
| 10033 | identity_enabled | User identity was enabled |
| 10034 | identity_disabled | User identity was disabled |
| 10040 | email_verified | User email was verified |
| 10041 | phone_verified | User phone was verified |
| 10050 | mfa_enabled | Multi-factor authentication was enabled |
| 10051 | mfa_disabled | Multi-factor authentication was disabled |
| 10060 | invitation_sent | User invitation was sent |
| 10061 | invitation_accepted | User invitation was accepted |
| 10062 | invitation_rejected | User invitation was rejected |
| 10070 | external_data_updated | User data was updated from external source |

#### Tenant Events (11001-11999)

| Code | Event | Description |
|------|-------|-------------|
| 11001 | tenant_created | New tenant was created |
| 11002 | tenant_updated | Tenant was updated |
| 11003 | tenant_deleted | Tenant was deleted |
| 11010 | tenant_user_added | User was added to tenant |
| 11011 | tenant_user_removed | User was removed from tenant |

#### Permission Events (12001-12999)

| Code | Event | Description |
|------|-------|-------------|
| 12001 | permission_created | New permission was created |
| 12002 | permission_updated | Permission was updated |
| 12003 | permission_deleted | Permission was deleted |
| 12010 | permission_assigned | Permission was assigned |
| 12011 | permission_revoked | Permission was revoked |
| 12020 | perm_set_created | New permission set was created |
| 12021 | perm_set_updated | Permission set was updated |
| 12022 | perm_set_deleted | Permission set was deleted |
| 12023 | perm_set_assigned | Permission set was assigned |
| 12024 | perm_set_revoked | Permission set was revoked |

#### Group Events (13001-13999)

| Code | Event | Description |
|------|-------|-------------|
| 13001 | group_created | New group was created |
| 13002 | group_updated | Group was updated |
| 13003 | group_deleted | Group was deleted |
| 13010 | group_member_added | Member was added to group |
| 13011 | group_member_removed | Member was removed from group |
| 13020 | group_mapping_created | Group mapping was created |
| 13021 | group_mapping_deleted | Group mapping was deleted |

#### API Key Events (14001-14999)

| Code | Event | Description |
|------|-------|-------------|
| 14001 | apikey_created | New API key was created |
| 14002 | apikey_updated | API key was updated |
| 14003 | apikey_deleted | API key was deleted |
| 14010 | apikey_validated | API key was validated |
| 14011 | apikey_validation_failed | API key validation failed |

#### Token Events (15001-15999)

| Code | Event | Description |
|------|-------|-------------|
| 15001 | token_created | New token was created |
| 15002 | token_used | Token was used |
| 15003 | token_expired | Token expired |
| 15004 | token_failed | Token validation failed |

### Error Codes (30xxx-34xxx)

#### Security Errors (30001-30999)

| Code | Function | Description |
|------|----------|-------------|
| 30001 | error.raise_30001 | API key/secret combination is not valid |
| 30002 | error.raise_30002 | Token is not valid or has expired |
| 30003 | error.raise_30003 | Token was created for different user |
| 30004 | error.raise_30004 | Token has already been used |
| 30005 | error.raise_30005 | Token does not exist |

#### Validation Errors (31001-31999)

| Code | Function | Description |
|------|----------|-------------|
| 31001 | error.raise_31001 | Either user group or target user id must not be null |
| 31002 | error.raise_31002 | Either permission set code or permission code must not be null |
| 31003 | error.raise_31003 | Either permission id or code must not be null |
| 31004 | error.raise_31004 | Either mapped object id or mapped role must not be empty |

#### Permission Errors (32001-32999)

| Code | Function | Description |
|------|----------|-------------|
| 32001 | error.raise_32001 | User does not have required permission |
| 32002 | error.raise_32002 | Permission does not exist |
| 32003 | error.raise_32003 | Permission is not assignable |
| 32004 | error.raise_32004 | Permission set does not exist |
| 32005 | error.raise_32005 | Permission set is not assignable |
| 32006 | error.raise_32006 | Permission set is not defined in this tenant |
| 32007 | error.raise_32007 | Parent permission does not exist |
| 32008 | error.raise_32008 | Some permissions are not assignable |

#### User/Group Errors (33001-33999)

| Code | Function | Description |
|------|----------|-------------|
| 33001 | error.raise_33001 | User does not exist |
| 33002 | error.raise_33002 | User is a system user |
| 33003 | error.raise_33003 | User is not in active state |
| 33004 | error.raise_33004 | User is locked out |
| 33005 | error.raise_33005 | User is not supposed to log in |
| 33006 | error.raise_33006 | User cannot be ensured for email provider |
| 33007 | error.raise_33007 | User identity is already in use |
| 33008 | error.raise_33008 | User identity is not in active state |
| 33009 | error.raise_33009 | User identity does not exist |
| 33010 | error.raise_33010 | Provider is not in active state |
| 33011 | error.raise_33011 | User group does not exist |
| 33012 | error.raise_33012 | User group is not active |
| 33013 | error.raise_33013 | User group is not assignable or is external |
| 33014 | error.raise_33014 | User group is a system group |
| 33015 | error.raise_33015 | User is not tenant or group owner |

#### Tenant Errors (34001-34999)

| Code | Function | Description |
|------|----------|-------------|
| 34001 | error.raise_34001 | User has no access to this tenant |

### Legacy Code Mapping (v1 Compatibility)

Old v1 error codes (52xxx) are still supported via aliases. See `016_functions_error.sql` for the complete mapping.


