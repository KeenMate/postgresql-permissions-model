# Permission Change Notifications (LISTEN/NOTIFY)

## Overview

The system sends real-time notifications via PostgreSQL's `LISTEN/NOTIFY` on the `permission_changes` channel whenever a permission-relevant mutation occurs. Backends listen on this channel and push "refetch permissions" events to affected clients via SSE/WebSocket.

## Setup

```
PostgreSQL (trigger fires)
    │
    ▼
pg_notify('permission_changes', JSON)     ← fires after COMMIT only
    │
    ▼
Backend (dedicated LISTEN connection)     ← NOT from connection pool (PgBouncer transaction mode doesn't support LISTEN)
    │
    ├─ resolve affected users (view query or in-memory lookup)
    ├─ debounce 100-200ms (bulk operations fire multiple triggers)
    │
    ▼
SSE / WebSocket → Clients refetch permissions
```

## Payload Format

All notifications share this structure:

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

- `event` — what happened
- `tenant_id` — affected tenant (`null` = all tenants)
- `target_type` — `"user"`, `"group"`, `"perm_set"`, `"system"`, `"provider"`, `"tenant"`, `"api_key"`
- `target_id` — the ID of the affected entity (`null` for provider events)
- `detail` — optional extra context
- `at` — timestamp

Payload limit: 8000 bytes (pg_notify hard limit). Only IDs are sent, never full data.

---

## All Notification Events

### Permission Assignment

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `permission_assigned` | `"user"` or `"group"` | user_id or group_id | `{ perm_set_id, permission_id }` | `"user"` → direct; `"group"` → `notify_group_users` |
| `permission_unassigned` | `"user"` or `"group"` | user_id or group_id | `{ perm_set_id, permission_id }` | `"user"` → direct; `"group"` → `notify_group_users` |

### Permission Set Content

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `perm_set_permissions_added` | `"perm_set"` | perm_set_id | `{ permission_id }` | `notify_perm_set_users` |
| `perm_set_permissions_removed` | `"perm_set"` | perm_set_id | `{ permission_id }` | `notify_perm_set_users` |
| `perm_set_updated` | `"perm_set"` | perm_set_id | `{ is_assignable }` | `notify_perm_set_users` |

### Group Membership

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `group_member_added` | `"user"` | user_id | `{ group_id }` | direct |
| `group_member_removed` | `"user"` | user_id | `{ group_id }` | direct |

### Group Status

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `group_enabled` | `"group"` | group_id | — | `notify_group_users` |
| `group_disabled` | `"group"` | group_id | — | `notify_group_users` |
| `group_deleted` | `"group"` | group_id | — | in-memory lookup (cascade already removed rows) |
| `group_type_changed` | `"group"` | group_id | `{ is_external }` | `notify_group_users` |

### Group Mappings

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `group_mapping_created` | `"group"` | group_id | `{ provider_code }` | `notify_group_users` |
| `group_mapping_deleted` | `"group"` | group_id | `{ provider_code }` | `notify_group_users` |

### User Status

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `user_disabled` | `"user"` | user_id | — | direct |
| `user_enabled` | `"user"` | user_id | — | direct |
| `user_locked` | `"user"` | user_id | — | direct |
| `user_unlocked` | `"user"` | user_id | — | direct |
| `user_deleted` | `"user"` | user_id | — | direct |

### Ownership

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `owner_created` | `"user"` | user_id | `{ scope: "tenant"/"group", user_group_id }` | direct |
| `owner_deleted` | `"user"` | user_id | `{ scope: "tenant"/"group", user_group_id }` | direct |

### Permission Tree

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `permission_assignability_changed` | `"system"` | permission_id | `{ full_code, is_assignable }` | `notify_permission_users` |

### Provider

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `provider_enabled` | `"provider"` | null | `{ provider_code }` | `notify_provider_users` |
| `provider_disabled` | `"provider"` | null | `{ provider_code }` | `notify_provider_users` |
| `provider_deleted` | `"provider"` | null | `{ provider_code }` | in-memory lookup (cascade already removed rows) |

### Tenant

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `tenant_deleted` | `"tenant"` | tenant_id | — | in-memory lookup (cascade already removed rows) |

### API Keys

| Event | target_type | target_id | detail | User Resolution |
|-------|-------------|-----------|--------|-----------------|
| `api_key_created` | `"api_key"` | api_key_id | `{ api_key }` | N/A (service-level) |
| `api_key_deleted` | `"api_key"` | api_key_id | `{ api_key }` | N/A (service-level) |

---

## Resolution Views

After receiving a notification, the backend queries the matching view to get affected user IDs.

| View | Key Column | Query Example |
|------|-----------|---------------|
| `auth.notify_group_users` | `user_group_id` | `select user_id from auth.notify_group_users where user_group_id = $1` |
| `auth.notify_perm_set_users` | `perm_set_id` | `select user_id from auth.notify_perm_set_users where perm_set_id = $1` |
| `auth.notify_permission_users` | `permission_id` | `select user_id from auth.notify_permission_users where permission_id = $1` |
| `auth.notify_provider_users` | `provider_code` | `select user_id from auth.notify_provider_users where provider_code = $1` |
| `auth.notify_tenant_users` | `tenant_id` | `select user_id from auth.notify_tenant_users where tenant_id = $1` |

For `target_type = "user"` events, the `target_id` is the `user_id` directly — no view needed.

---

## Backend Routing Logic

| `target_type` | Live Events | Delete Events |
|---------------|-------------|---------------|
| `"user"` | Direct from payload `target_id` | Same |
| `"group"` | Query `notify_group_users` | In-memory lookup (backend tracks group membership) |
| `"perm_set"` | Query `notify_perm_set_users` | N/A |
| `"system"` | Query `notify_permission_users` | N/A |
| `"provider"` | Query `notify_provider_users` | In-memory lookup (backend tracks provider users) |
| `"tenant"` | Query `notify_tenant_users` | In-memory lookup (backend tracks tenant users) |
| `"api_key"` | Service-level handling | Same |

Delete events (`group_deleted`, `provider_deleted`, `tenant_deleted`) fire after COMMIT, meaning the cascade has already removed the rows from the resolution views. The backend must use its own in-memory map of connected users and their tenant/group/provider memberships.

---

## Debouncing

Bulk operations (e.g. `process_external_group_member_sync`) fire one trigger per row, but `pg_notify` batches all notifications and delivers them at COMMIT. The backend receives them all at once and should:

1. Collect notifications for 100-200ms
2. Deduplicate by `(tenant_id, target_type, target_id)`
3. Send one `REFETCH_PERMISSIONS` event per affected user

---

## Reconnection

If the LISTEN connection drops:

1. Reconnect and re-issue `LISTEN permission_changes`
2. Notifications sent during the gap are lost (pg_notify is fire-and-forget)
3. Optionally trigger a full permission refetch for all connected clients as a safety net

Cache invalidation on the DB side is the correctness mechanism. Notifications are an optimization for client freshness — missing one just means a slightly delayed refetch.
