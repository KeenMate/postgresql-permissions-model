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
- **Comprehensive audit logging** for all security events
- **Permission caching** for performance

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

### Schema Security Model
- **`public`** & **`auth`** - Always validate permissions
- **`internal`** - For trusted contexts (no permission checks)
- **`unsecure`** - Security system internals only

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

## Database event codes

### Common

| Event code | Description       |
|------------|-------------------|
| 50003      | Permission denied |

### Security

| Event code | Description                            |
|------------|----------------------------------------|
| 50001      | Tenant created                         |
| 50002      | Tenant updated                         |
| 50003      | Tenant deleted                         |
| 50004      | Assign tenant owner                    |
| 50005      | Get tenant users                       |
| 50006      | Get tenant groups                      |
| 50011      | Provider created                       |
| 50012      | Provider updated                       |
| 50013      | Provider deleted                       |
| 50014      | Provider enabled                       |
| 50015      | Provider disabled                      |
| 50016      | Get provider users                     |
| 50101      | User created                           |
| 50102      | User updated                           |
| 50103      | User deleted                           |
| 50104      | User enabled                           |
| 50105      | User disabled                          |
| 50106      | User unlocked                          |
| 50107      | User locked                            |
| 50108      | User identity enabled                  |
| 50109      | User identity disabled                 |
| 50131      | User added to group                    |
| 50133      | User deleted from group                |
| 50134      | User identity created                  |
| 50135      | User identity deleted                  |
| 50136      | User password changed                  |
| 50201      | Group created                          |
| 50202      | Group updated                          |
| 50203      | Group deleted                          |
| 50204      | Group enabled                          |
| 50205      | Group disabled                         |
| 50206      | Group unlocked                         |
| 50207      | Group locked                           |
| 50208      | Group set as external group            |
| 50209      | Group set as hybrid group              |
| 50210      | User requested group members list      |
| 50211      | User requested user group info         |
| 50231      | Group mapping created                  |
| 50233      | Group mapping deleted                  |
| 50301      | Permission set created                 |
| 50302      | Permission set updated                 |
| 50303      | Permission set deleted                 |
| 50304      | Permission assigned                    |
| 50305      | Permission unassigned                  |
| 50306      | Permission assignability changed       |
| 50307      | Permission set copied                  |
| 50311      | Permissions added to perm set          |
| 50313      | Permissions removed from perm set      |
| 50331      | Permission created                     |
| 50401      | Token created                          |
| 50402      | Token validated                        |
| 50403      | Token set as used                      |
| 50501      | API key created                        |
| 50502      | API key updated                        |
| 50503      | API key deleted                        |
| 50504      | API key perm set/permission assigned   |
| 50505      | API key perm set/permission unassigned |
| 50506      | API key secret updated                 |

### Security Error codes

| Event code | Description                                                                           |
|------------|---------------------------------------------------------------------------------------|
| 52101      | Cannot ensure user for email provider                                                 |
| 52102      | User cannot register user because the identity is already in use                      |
| 52103      | User does not exist                                                                   |
| 52104      | User is a system user                                                                 |
| 52105      | User is not active                                                                    |
| 52106      | User is locked                                                                        |
| 52107      | Provider is not active                                                                |
| 52108      | User has no access to tenant                                                          |
| 52109      | User has no correct permission in tenant                                              |
| 52110      | User provider identity is not active                                                  |
| 52111      | User provider identity does not exist                                                 |
| 52112      | User is not supposed to log in                                                        |
| 52171      | User group not found                                                                  |
| 52172      | User cannot be added to group because the group is not active                         |
| 52173      | User cannot be added to group because it's either not assignable or an external group |
| 52174      | Either mapped object id or role must not be empty                                     |
| 52175      | Permission set is not assignable                                                      |
| 52176      | Permission is not assignable                                                          |
| 52177      | Permission set is not defined in tenant                                               |
| 52178      | Some permission is not assignable                                                     |
| 52179      | Parent permission does not exist                                                      |
| 52271      | User group cannot be deleted because it's a system group                              |
| 52272      | Either user group id or target user id has to be not null                             |
| 52273      | Either permission set code or permission code has to be not null                      |
| 52274      | Either permission id or code has to be not null                                       |
| 52275      | Permission does not exist                                                             |
| 52276      | The same token is already used                                                        |
| 52277      | Token does not exist                                                                  |
| 52278      | Token is not valid or has expired                                                     |
| 52279      | Token was created for different user                                                  |
| 52280      | User is not tenant owner                                                              |
| 52281      | User is not tenant or group owner                                                     |
| 52281      | User is not tenant or group owner                                                     |


