# Resource Access (ACL) System

Resource-level access control layered on top of RBAC. While RBAC controls **what actions** a user can perform globally (e.g. "can create folders"), the ACL system controls **which specific resources** they can act on (e.g. "can read folder #42").

---

## Tables

### `const.resource_type`

Registry of valid resource types. Global (not tenant-specific).

| Column | Type | Description |
|--------|------|-------------|
| `code` | text PK | Type identifier (e.g. `folder`, `document`) |
| `title` | text | Display name |
| `description` | text | Optional description |
| `is_active` | boolean | Whether type is active |
| `source` | text | Origin tracker (e.g. `documents_app`) |

### `const.resource_access_flag`

Registry of valid access flags. Extensible — add custom flags by inserting rows.

| Column | Type | Description |
|--------|------|-------------|
| `code` | text PK | Flag identifier |
| `title` | text | Display name |
| `source` | text | Origin tracker |

**Built-in flags:**

| Flag | Meaning |
|------|---------|
| `read` | View/read the resource |
| `write` | Create/modify the resource |
| `delete` | Delete the resource |
| `share` | Grant access to others |

Custom flags can be added (e.g. `export`, `comment`, `subscribe`). All flags work uniformly in grant/deny/check operations.

### `auth.resource_access`

Core ACL table. One row = one flag for one user or group on one resource. Partitioned by `resource_type` (list partitioning) — each type gets its own partition (e.g. `auth.resource_access_folder`).

| Column | Type | Description |
|--------|------|-------------|
| `resource_access_id` | bigint (identity) | PK (composite with resource_type) |
| `tenant_id` | integer | Tenant FK (cascade delete) |
| `resource_type` | text | FK to `const.resource_type` |
| `resource_id` | bigint | Application-specific resource ID |
| `user_id` | bigint | Target user (NULL if group grant) |
| `user_group_id` | integer | Target group (NULL if user grant) |
| `access_flag` | text | FK to `const.resource_access_flag` |
| `is_deny` | boolean | `false` = grant, `true` = deny |
| `granted_by` | bigint | User who created this ACL entry |
| `created_at/by` | audit | Standard audit fields |
| `updated_at/by` | audit | Standard audit fields |

**Constraints:**
- Either `user_id` or `user_group_id` must be set (not both, not neither)
- Unique per `(resource_type, tenant_id, resource_id, user_id, access_flag)` for user grants
- Unique per `(resource_type, tenant_id, resource_id, user_group_id, access_flag)` for group grants

---

## Access Check Algorithm

When `auth.has_resource_access()` is called, checks happen in this order:

1. **System user** (id=1) → always allowed
2. **Tenant owner** → always allowed
3. **User-level deny** (`is_deny=true`) → **blocked**, overrides everything
4. **User-level grant** (`is_deny=false`) → allowed
5. **Group-level grant** (via `user_group_member` + active group) → allowed
6. **No matching row** → denied

**Key rule:** User-level deny beats all group grants. This is how you create exceptions — even if Bob is in the "Editors" group with write on a folder, a user-level deny on Bob blocks him specifically.

---

## Deny Model

- Denies are **user-level only** — you cannot deny a group
- Denies are **per-flag** — deny `read` doesn't affect `write`
- Denies are **explicit** — must be set with `auth.deny_resource_access()`
- To remove a deny, use `auth.revoke_resource_access()` (deletes the deny row)

---

## Group Access

1. **Grant:** Call `auth.grant_resource_access()` with `_user_group_id` to grant flags to a group
2. **Membership resolution:** Access check joins `resource_access` → `user_group_member` → `user_group` (must be `is_active=true`)
3. **Effective flags:** `auth.get_resource_access_flags()` returns group grants with source = group title
4. All group types (internal, external, hybrid) work equally with resource access

---

## Functions

### Checking Access

#### `auth.has_resource_access`

Check if user has a specific flag on a resource.

```sql
auth.has_resource_access(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _required_flag  text    default 'read',
    _tenant_id      integer default 1,
    _throw_err      boolean default true
) returns boolean
```

```sql
-- Throws if denied (default)
perform auth.has_resource_access(_user_id, _corr_id, 'folder', _folder_id, 'read', _tenant_id);

-- Silent check
if auth.has_resource_access(_user_id, _corr_id, 'folder', _folder_id, 'write', _tenant_id, _throw_err := false) then
    -- user has write access
end if;
```

#### `auth.filter_accessible_resources`

Bulk filter — returns subset of resource IDs that user can access.

```sql
auth.filter_accessible_resources(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_ids   bigint[],
    _required_flag  text    default 'read',
    _tenant_id      integer default 1
) returns table(__resource_id bigint)
```

```sql
select f.folder_id, f.title
from public.folder f
inner join auth.filter_accessible_resources(
    _user_id, _corr_id, 'folder',
    (select array_agg(folder_id) from public.folder where tenant_id = _tenant_id),
    'read', _tenant_id
) acl on acl.__resource_id = f.folder_id;
```

#### `auth.get_resource_access_flags`

Returns all effective flags a user has on a resource, with their source.

```sql
auth.get_resource_access_flags(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns table(__access_flag text, __source text)
```

Source values: `system` (system user), `owner` (tenant owner), `direct` (user-level grant), or group title (group-level grant).

### Granting Access

#### `auth.grant_resource_access`

Grant flags to a user or group. Idempotent — re-granting is a no-op, granting over a deny flips it to a grant.

```sql
auth.grant_resource_access(
    _created_by     text,
    _user_id        bigint,          -- caller (must have resources.grant_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
```

```sql
-- Grant to user
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'folder', _folder_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);

-- Grant to group
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'folder', _folder_id,
    _user_group_id := _group_id, _access_flags := array['read','write']);
```

### Denying Access

#### `auth.deny_resource_access`

Explicit deny — user-level only. Overrides all group grants for that user.

```sql
auth.deny_resource_access(
    _created_by     text,
    _user_id        bigint,          -- caller (must have resources.deny_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint,          -- required (no group denies)
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
```

```sql
perform auth.deny_resource_access('app', _admin_id, _corr_id, 'folder', _folder_id,
    _target_user_id := _user_id, _access_flags := array['read']);
```

### Revoking Access

#### `auth.revoke_resource_access`

Revoke specific flags (or all flags if `_access_flags` is NULL).

```sql
auth.revoke_resource_access(
    _deleted_by     text,
    _user_id        bigint,          -- caller (must have resources.revoke_access)
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default null,   -- NULL = revoke all
    _tenant_id      integer default 1
) returns bigint                             -- count of deleted rows
```

```sql
-- Revoke specific flags
select auth.revoke_resource_access('app', _admin_id, _corr_id, 'folder', _folder_id,
    _target_user_id := _user_id, _access_flags := array['write']);

-- Revoke all flags
select auth.revoke_resource_access('app', _admin_id, _corr_id, 'folder', _folder_id,
    _target_user_id := _user_id);
```

#### `auth.revoke_all_resource_access`

Remove ALL ACL rows for a resource (all users, all groups, all flags). Used when deleting resources.

```sql
auth.revoke_all_resource_access(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns bigint
```

### Querying Grants

#### `auth.get_resource_grants`

List all grants and denies on a resource.

```sql
auth.get_resource_grants(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    bigint,
    _tenant_id      integer default 1
) returns table(
    __resource_access_id bigint,
    __user_id            bigint,
    __user_display_name  text,
    __user_group_id      integer,
    __group_title        text,
    __access_flag        text,
    __is_deny            boolean,
    __granted_by         bigint,
    __granted_by_name    text,
    __created_at         timestamptz
)
```

#### `auth.get_user_accessible_resources`

List all resources a user can access with a given flag.

```sql
auth.get_user_accessible_resources(
    _user_id         bigint,          -- caller
    _correlation_id  text,
    _target_user_id  bigint,          -- whose resources to query
    _resource_type   text,
    _access_flag     text    default 'read',
    _tenant_id       integer default 1
) returns table(
    __resource_id  bigint,
    __access_flags text[],
    __source       text
)
```

---

## Registering New Resource Types

```sql
-- 1. Register the type
insert into const.resource_type (code, title) values ('report', 'Reports');

-- 2. Create the partition (auto-creates auth.resource_access_report)
perform unsecure.ensure_resource_access_partition('report');

-- 3. Grant/check access on 'report' resources
perform auth.grant_resource_access('app', _admin_id, _corr_id, 'report', _report_id,
    _target_user_id := _user_id, _access_flags := array['read','write']);
```

---

## Integration Pattern (RBAC + ACL)

Every application function follows the dual-check pattern:

```sql
create or replace function public.get_folder(
    _created_by text, _user_id bigint, _correlation_id text,
    _tenant_id integer, _folder_id bigint
) returns table(...) as $$
begin
    -- 1. RBAC: Can user perform this action at all?
    perform auth.has_permission(_user_id, _correlation_id, 'documents.read_folders', _tenant_id);

    -- 2. ACL: Can user access THIS specific resource?
    perform auth.has_resource_access(_user_id, _correlation_id, 'folder', _folder_id, 'read', _tenant_id);

    -- 3. Do the work
    return query select ... from public.folder where folder_id = _folder_id;
end;
$$ language plpgsql;
```

For bulk queries, use `filter_accessible_resources`:

```sql
create or replace function public.get_folders(
    _created_by text, _user_id bigint, _correlation_id text,
    _tenant_id integer, _parent_folder_id bigint default null
) returns table(...) as $$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'documents.read_folders', _tenant_id);

    return query
    select f.*
    from public.folder f
    inner join auth.filter_accessible_resources(
        _user_id, _correlation_id, 'folder',
        (select array_agg(folder_id) from public.folder where tenant_id = _tenant_id),
        'read', _tenant_id
    ) acl on acl.__resource_id = f.folder_id;
end;
$$ language plpgsql;
```

---

## RBAC Permissions Required

Functions in the `auth` schema require these RBAC permissions:

| Permission | Required by |
|------------|-------------|
| `resources.grant_access` | `auth.grant_resource_access()` |
| `resources.deny_access` | `auth.deny_resource_access()` |
| `resources.revoke_access` | `auth.revoke_resource_access()`, `auth.revoke_all_resource_access()` |
| `resources.get_grants` | `auth.get_resource_grants()`, `auth.get_user_accessible_resources()` |
| `resources.create_resource_type` | `auth.create_resource_type()` |

---

## Error Codes

| Code | Meaning |
|------|---------|
| 35001 | User has no access to resource (or explicitly denied) |
| 35002 | Neither user_id nor user_group_id provided in grant/revoke |
| 35003 | Resource type doesn't exist or is inactive |
| 35004 | Access flag doesn't exist |

## Journal Event Codes

| Code | Event | Function |
|------|-------|----------|
| 18001 | resource_type_created | `auth.create_resource_type()` |
| 18010 | resource_access_granted | `auth.grant_resource_access()` |
| 18011 | resource_access_revoked | `auth.revoke_resource_access()` |
| 18012 | resource_access_denied | `auth.deny_resource_access()` |
| 18013 | resource_access_bulk_revoked | `auth.revoke_all_resource_access()` |

---

## Partitioning

The `auth.resource_access` table is list-partitioned by `resource_type`:

```
auth.resource_access (parent)
├── auth.resource_access_folder    (resource_type = 'folder')
├── auth.resource_access_document  (resource_type = 'document')
└── auth.resource_access_default   (catches unregistered types)
```

Partitions are auto-created by `unsecure.ensure_resource_access_partition()`. PostgreSQL prunes partitions automatically — queries filtered by `resource_type` only scan the relevant partition.

---

## Documents App Example

The documents app in this repository demonstrates the full system:

- **Resource types:** `folder`, `document`
- **RBAC permissions:** `documents.create_folder`, `documents.read_folders`, `documents.delete_folder`, `documents.create_document`, `documents.read_documents`, `documents.delete_document`
- **Permission set:** "Document user" bundles all document + resource permissions
- **Users:** Alice (admin + document_user), Bob (document_user, Editors group member), Charlie (document_user), Dave (no permissions)
- **ACL grants:** Alice = full access on all folders, Editors group = read+write on Projects, Charlie = read on Shared, Bob = deny read on Private
- **41 tests** covering folder/document CRUD, group inheritance, deny overrides, share workflow, and revocation
