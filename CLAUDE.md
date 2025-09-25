# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a standalone PostgreSQL database model that provides complete tenant/user/group/permissions management for any PostgreSQL project. It's a self-contained SQL-based framework that gives applications comprehensive handling of multi-tenancy, user management, hierarchical permissions, permission sets, and role-based access control. The separate `../keen-auth-permissions` library is built on top of this database model to provide application-level integration.

## Key Architecture Components

### Database Schema Organization & Security Model
The system uses multiple PostgreSQL schemas with distinct security boundaries:

**Permission-Checked Schemas (always validate permissions):**
- `public` - Application business functions with permission checks (kept clean for app-specific functions)
- `auth` - Security functions with permission checks (same as public, but security-focused)

**No Permission Checks (trusted contexts only):**
- `internal` - Business functions without permission checks (wrapped by public functions or called from secure app context)
- `unsecure` - Security-related internal functions only (NOT for unprotected business logic)

**Utility & Configuration:**
- `helpers` - Utility functions (random strings, code generation, ltree operations)
- `error` - Error handling and exception functions
- `const` - Constants and configuration tables (user types, event types, system parameters)
- `ext` - PostgreSQL extensions (ltree, uuid-ossp, unaccent, pg_trgm)
- `stage` - Staging tables for data imports (e.g., external group members)

**Key Security Principle**:
- `public` and `auth` schemas ALWAYS check permissions (except utility functions like get_app_version)
- `internal` is for business logic that's already permission-checked at a higher level
- `unsecure` is ONLY for security-system internals, never for business functions

### Core Entities
This system manages the complete lifecycle of authorization entities:

**Multi-Tenancy:**
- **Tenants** (`auth.tenant`) - Multi-tenancy support with isolated permissions and data
- **Tenant Users** (`auth.tenant_user`) - Links users to tenants they have access to
- **User Tenant Preferences** (`auth.user_tenant_preference`) - Per-tenant user settings/preferences
- **Ownership** (`auth.owner`) - Tracks tenant owners and group owners

**User Management:**
- **Users** (`auth.user_info`) - Core user data
- **User Identity** (`auth.user_identity`) - Provider-specific identities (Windows GUID, AzureAD UID, etc.)
- **User Data** (`auth.user_data`) - Extensible custom fields per application needs
- **User Permission Cache** (`auth.user_permission_cache`) - Cached permission calculations for performance

**Groups & Mappings:**
- **Groups** (`auth.user_group`) - Three types: internal, external, and hybrid membership models
- **Group Mappings** (`auth.user_group_mapping`) - Maps external provider groups/roles to internal groups
- **Group Members** (`auth.user_group_member`) - Direct group membership for internal/hybrid groups

**Permissions & Sets:**
- **Permissions** (`auth.permission`) - Global hierarchical permission tree using ltree
- **Permission Sets** (`auth.perm_set`) - Tenant-specific permission collections
- **Permission Set Permissions** (`auth.perm_set_perm`) - Links permissions to permission sets
- **Permission Assignments** (`auth.permission_assignment`) - Assigns permissions/sets to users/groups

**Authentication & Security:**
- **Providers** (`auth.provider`) - External identity provider configurations
- **Tokens** (`auth.token`) - Short-lived authentication tokens
- **API Keys** (`auth.api_key`) - Long-lived service authentication with technical users

**Audit & Logging:**
- **User Events** (`auth.user_event`) - Comprehensive audit log for all security events
- **Journal** (`journal`) - General-purpose journaling/logging table

### Permission Model
The system implements a hierarchical permission model with clear separation between permissions and permission sets:

**Permissions (Global)**:
- Hierarchical structure using PostgreSQL's ltree extension
- Examples: `users`, `users.create_user`, `users.read_users.read_gdpr_protected_data`
- Can have unlimited nesting levels based on application needs
- **Global across all tenants** - same permission structure for everyone

**Permission Sets (Tenant-Specific)**:
- Collections of permissions grouped by role/function
- **Tenant-specific** - each tenant can have different permission sets with different permission combinations
- Reusable across users and groups within a tenant

**Assignment Model**:
- Permissions are assigned via `permission_assignment` table
- Can be assigned directly to users OR to groups (users inherit from group membership)
- Assignment happens through permission sets or individual permissions

## Database Object Tracking

**IMPORTANT**: Before looking for any database object (function, table, view, etc.), always check `db-objects.md` first to find the latest definition location.

- `db-objects.md` - Complete tracking table of all 284+ database objects with:
  - Schema, object name, and type
  - Latest update file and line number
  - Complete update history across all migration files
  - Separation of migration vs ad-hoc updates
- `extract-db-objects.py` - Python script to regenerate the tracking table
- `db-objects.json` - JSON version for programmatic access

**Usage**: When asked about any function like `auth.has_permission`, first check `db-objects.md` to see it's defined in `004_create_permissions.sql:1588` with 1 total update.

**Key Columns**:
- **Last File**: The most recent file where the object was defined/modified
- **Line**: The exact line number in that file where the current definition starts
- **Migration Updates**: Chronological history of all changes (newest first)
- **Ad-hoc Updates**: Any updates from ad-hoc scripts (if DBADHOCDIRECTORY is set)

## Development Commands

### Database Setup and Migration
Use the PowerShell script `debee.ps1` for all database operations:

```powershell
# Full database setup (recreate, restore, update)
./debee.ps1 -Operations fullService

# Individual operations
./debee.ps1 -Operations recreateDatabase
./debee.ps1 -Operations restoreDatabase
./debee.ps1 -Operations updateDatabase
./debee.ps1 -Operations preUpdateScripts
./debee.ps1 -Operations postUpdateScripts

# Run specific migration range
./debee.ps1 -Operations updateDatabase -UpdateStartNumber 001 -UpdateEndNumber 010

# Use different environment
./debee.ps1 -Environment prod -Operations updateDatabase
```

### Legacy Windows Batch Script
For simple setup on Windows:
```batch
run.bat
```

### Environment Configuration
- Primary config: `debee.env`
- Local overrides: `.debee.env` (gitignored)
- Environment-specific: `debee.{environment}.env`

Key environment variables:
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` - PostgreSQL connection
- `DBDESTDB` - Target database name (default: postgresql_permissionmodel)
- `DBUPDATESTARTNUMBER`, `DBUPDATEENDNUMBER` - Migration script ranges
- `DBBACKUPFILE`, `DBBACKUPTYPE` - Restore configuration

## SQL Migration Files

### Naming Convention
Files follow pattern: `XXX_description.sql` where XXX is a 3-digit number
- `000_create_database.sql` - Initial database creation
- `001_create_basic_structure.sql` - Core schemas and extensions
- `002_create_version_management.sql` - Database versioning system (`__version` table)
- `003_create_helpers.sql` - Helper functions
- `004_create_permissions.sql` - Main permissions system (largest file ~217KB)
- `007-024_update_permissions_v1-X.sql` - Incremental updates
- `99_fix_permissions.sql` - Post-update permission fixes

### Version Management
Simple version tracking using the `public.__version` table with component support:

```sql
-- Start version update (creates record with start timestamp)
select * from public.start_version_update('1.16', 'Description of update', 'Optional longer description', 'component_name');

-- Migration content here

-- Mark version complete (sets finish timestamp)
select * from public.stop_version_update('1.16', 'component_name');

-- Check if version already applied
select public.check_version('1.16', 'component_name');
```

**Version table structure**:
- Tracks `component`, `version`, `title`, `description`
- Records `execution_started` and `execution_finished` timestamps
- Supports multiple components (defaults to 'main')

## Key Functions and Usage Patterns

### User Management Functions
The user system uses three main tables for flexible multi-provider support and extensibility:

**Core User Management (`user_info` table)**:
- `auth.register_user()` - User registration and initial setup
- `auth.enable_user()` / `auth.disable_user()` - User status management
- `auth.lock_user()` / `auth.unlock_user()` - Account security controls
- `auth.update_user_password()` - Password management
- `auth.add_user_to_default_groups()` - Automatic group assignment

**Identity Provider Management (`user_identity` table)**:
- `auth.ensure_user_from_provider()` - User provisioning from external providers
- `auth.create_user_identity()` - Add new identity provider to existing user
- `auth.enable_user_identity()` / `auth.disable_user_identity()` - Control provider access
- Multiple identities per user: Windows GUID, AzureAD UID, Google ID, etc.
- **Last used provider determines permissions** - `provider_groups` and `provider_roles` from most recent login drive permission calculations

**Extensible User Data (`user_data` table)**:
- `auth.update_user_data()` - Update custom user fields
- **Flexible schema**: Add any columns needed (e.g., `employee_number`, `has_children`, `is_casual_driver`)
- **Alternative approach**: Create custom tables and reference `auth.user_info.user_id` as foreign key
- No fixed structure - adapt to application-specific requirements

### Authorization Functions
Core permission checking for any PostgreSQL application:
- `auth.has_permission(_tenant_id, _user_id, _perm_code, _throw_err := true)` - Single permission check
- `auth.has_permissions(_tenant_id, _user_id, _perm_codes[], _throw_err := true)` - Multiple permissions check
- `_throw_err` parameter allows silent permission checking without throwing unauthorized exceptions
- `auth.create_auth_event()` - Comprehensive audit logging
- Functions check both direct user permissions and inherited group permissions

### Permission Management

**Global Permission Structure**:
- `auth.create_permission_by_path()` / `auth.create_permission_by_code()` - Create hierarchical permissions
- Permissions use ltree paths like `users.create_user` or `users.read_users.read_gdpr_protected_data`
- Same permission structure across all tenants

**Tenant-Specific Permission Sets**:
- `auth.create_perm_set()` - Create tenant-specific permission sets (e.g., "Admin", "Manager", "Viewer")
- `auth.add_perm_set_permissions()` - Add global permissions to tenant permission sets
- `auth.copy_perm_set()` / `auth.duplicate_perm_set()` - Permission set duplication within/across tenants

**Assignment to Users/Groups**:
- `auth.assign_permission()` / `auth.unassign_permission()` - Assign permission sets or individual permissions
- Can assign directly to users or to groups (users inherit from group membership)
- All assignments stored in `permission_assignment` table

### Group Management
The system supports three group types for different authentication scenarios:

**Internal Groups** - Traditional membership stored in database:
- `auth.create_user_group()` / `auth.update_user_group()` - Group lifecycle
- `auth.create_user_group_member()` / `auth.delete_user_group_member()` - Direct membership management

**External Groups** - Membership determined by external identity provider mappings:
- `auth.create_external_user_group()` - Create groups that rely solely on external mappings
- `auth.create_user_group_mapping()` / `auth.delete_user_group_mapping()` - Map external groups to internal permission groups
- `auth.set_user_group_as_external()` - Configure group to use only external mappings
- Works with any identity provider: Windows Authentication, AzureAD, Google, Facebook, KeyCloak, LDAP, etc.
- Maps both `provider_groups` AND `provider_roles` - flexible for different provider implementations

**Hybrid Groups** - Combination of both membership models:
- `auth.set_user_group_as_hybrid()` - Allow both direct members and external mappings
- Supports both manual membership and external group synchronization

**Example Flow**:
1. User logs in via AzureAD → System updates `user_identity` with `provider_groups` and `provider_roles`
2. System marks this identity as "last used" for the user
3. Permission calculation uses the `provider_groups`/`provider_roles` from last used identity
4. System checks group mappings → Finds user's AzureAD group/role maps to "Super Admins"
5. User gets Super Admins permissions without being explicitly added as a member

**Multi-Identity Support**: Same user can have Windows Auth GUID, AzureAD UID, Google ID - permissions calculated from whichever they last used to login.

### Tenant Management
- `auth.create_tenant()` / `auth.update_tenant()` - Multi-tenant setup
- `auth.assign_tenant_owner()` - Tenant ownership assignment
- `auth.get_tenant_users()` / `auth.get_tenant_groups()` - Tenant queries

### API Key Management
API keys provide service-to-service authentication with a unique approach:
- `auth.create_api_key()` - Creates API key AND a "technical user" in `user_info`
- `auth.update_api_key()` / `auth.delete_api_key()` - API key lifecycle
- `auth.update_api_key_secret()` - Rotate API key secrets
- **Technical User Pattern**: Each API key gets its own user entry to maintain database consistency
- API keys can be assigned permission sets or individual permissions like regular users
- This design allows all permission checks to work uniformly for both human users and API services

### Common Integration Pattern
Most stored procedures should start with permission checks:
```sql
-- Example procedure pattern with exception throwing
if not auth.has_permission(_tenant_id, _user_id, 'orders.cancel_order') then
    perform auth.throw_no_permission(_tenant_id, _user_id, 'orders.cancel_order');
end if;

-- OR use built-in exception throwing (default behavior)
perform auth.has_permission(_tenant_id, _user_id, 'orders.cancel_order');

-- OR silent check without exceptions
if auth.has_permission(_tenant_id, _user_id, 'orders.cancel_order', _throw_err := false) then
    -- user has permission, proceed
else
    -- user lacks permission, handle gracefully
end if;
```

**Important SQL Convention**: Always use fully qualified schema names (e.g., `auth.has_permission`, `public.__version`) to avoid "cannot find table/function" errors due to search_path issues.

## Error Codes
The system uses structured error codes (50001-52999) for different categories:
- 50001-50999: Informational events (tenant created, user updated, etc.)
- 52001-52999: Security errors (user not found, permission denied, etc.)

Refer to `readme.md:16-124` for complete error code documentation.

## Testing and Validation
- No specific test framework - manual testing through SQL scripts
- Use `999-examples.sql` for testing scenarios
- Always test permission inheritance and tenant isolation
- Verify audit events are properly logged

## Important Notes
- This is a pure PostgreSQL solution - no external dependencies beyond PostgreSQL extensions
- All timestamps use `timestamptz` for timezone awareness
- **Schema Security Model**: `public` and `auth` always check permissions; `internal` is for trusted contexts; `unsecure` is only for security internals
- **SQL Convention**: Always use fully qualified schema names (e.g., `auth.has_permission`, `public.__version`) to prevent search_path related errors
- **Group Mapping Strategy**: Supports internal, external, and hybrid group membership models for flexible integration with any identity provider (Windows Auth, AzureAD, Google, Facebook, KeyCloak, LDAP, etc.)
- **Extensible User Data**: `user_data` table can be modified with custom columns OR create separate tables referencing `user_info.user_id`
- Permission caching is implemented - use `unsecure.clear_permission_cache()` when needed
- **API Keys as Technical Users**: Each API key creates a technical user in `user_info`, allowing uniform permission handling across human and service accounts
- System includes comprehensive audit logging for all security events
- The `../keen-auth-permissions` library provides application-level wrappers around these SQL functions
- Can be integrated into any PostgreSQL project by running the migration scripts
- External group mappings eliminate need to sync user membership - permissions are resolved dynamically from last used identity's `provider_groups`/`provider_roles`
- Users can have multiple identities (Windows, AzureAD, Google, etc.) but permissions calculated from most recent login provider