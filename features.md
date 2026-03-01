# Feature list

Features present in the PostgreSQL Permissions Model.

### Multi-Tenancy
- create/update/delete tenant
- assign tenant owner / group owner
- get tenants / groups / members / permissions
- tenant-isolated permission sets and data

### Users
- register user
- enable/disable
- lock/unlock
- change password
- get user identity + by email
- add to default groups
- get user events
- get/update user data
- multiple identity providers per user
- search users with pagination

### Identity Providers
- create/update/delete
- enable/disable
- ensure (idempotent create)
- capability flags (allows_group_mapping, allows_group_sync)
- get provider users

### Groups
- CRUD (internal, external, hybrid types)
- get/add/remove members
- get/add/remove mappings
- external group sync from providers
- search groups with member counts

### Permissions
- create/update/delete permission (hierarchical ltree)
- create/update/delete permission set (tenant-specific)
- assign/unassign permission / permission set
- has_permission / has_permissions (single & batch check)
- permission caching with automatic invalidation
- short codes for hierarchical permission lookup
- search permissions with pagination

### Resource Access (ACL)
- register resource types with auto-partitioning
- grant access (user or group, multiple flags)
- deny access (user-level, overrides group grants)
- revoke access (specific flags or all)
- has_resource_access check (deny-overrides algorithm)
- filter_accessible_resources (bulk filter)
- get_resource_access_flags (effective flags with source)
- get_resource_grants / get_user_accessible_resources

### Tokens
- create
- validate
- set as used

### API Keys
- create (with technical user)
- update / delete
- rotate secret
- validate

### Language & Translation
- language CRUD with default flags (frontend/backend/communication)
- translation CRUD with accent-insensitive search
- copy translations between languages (with overwrite option)
- full-text search (tsvector) and normalized text search (trigram)
- get group translations as jsonb
- search translations with pagination

### Journal / Audit Logging
- multi-key journal entries
- request context tracking (IP, user agent, etc.)
- range-partitioned by month (journal + user_event)
- search journal with filters (category, entity, full-text, date range)
- unified user audit trail
- security event queries
- data retention with partition-based purge
- storage mode switch (local / notify / both)

### Real-Time Notifications
- LISTEN/NOTIFY for permission changes
- resolution views for affected users
- fire-and-forget with cache invalidation safety net

### System Parameters
- runtime configuration via const.sys_param
- journal level control (all / update / none)
- retention days, storage mode, partition config
- permission cache timeout

### Service Accounts
- dedicated service users (IDs 1-999 reserved)
- registrator, authenticator, token_manager, api_gateway, group_syncer, data_processor
- least-privilege permission sets per service
