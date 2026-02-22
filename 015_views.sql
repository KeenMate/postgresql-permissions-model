/*
 * Views
 * =====
 *
 * All database views
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace view auth.active_user_groups
            (user_group_id, is_system, is_external, is_assignable, is_active, is_default, group_title, group_code, tenant_id, tenant_code, tenant_title) as
SELECT ug.user_group_id,
    ug.is_system,
    ug.is_external,
    ug.is_assignable,
    ug.is_active,
    ug.is_default,
    ug.title AS group_title,
    ug.code AS group_code,
    ug.tenant_id,
    t.code AS tenant_code,
    t.title AS tenant_title
   FROM auth.user_group ug
     LEFT JOIN auth.tenant t ON ug.tenant_id = t.tenant_id
  WHERE ug.is_active;

create or replace view auth.effective_permissions
            (perm_set_id, perm_set_code, perm_set_title, perm_set_is_assignable, perm_set_source, permission_id, permission_title, permission_code, permission_short_code, permission_is_assignable, permission_source) as
SELECT DISTINCT ps.perm_set_id,
    ps.code AS perm_set_code,
    ps.title AS perm_set_title,
    ps.is_assignable AS perm_set_is_assignable,
    ps.source AS perm_set_source,
    sp.permission_id,
    sp.title AS permission_title,
    sp.full_code AS permission_code,
    sp.short_code AS permission_short_code,
    sp.is_assignable AS permission_is_assignable,
    sp.source AS permission_source
   FROM auth.perm_set ps
     JOIN auth.perm_set_perm psp ON ps.perm_set_id = psp.perm_set_id
     JOIN auth.permission p ON psp.permission_id = p.permission_id
     JOIN auth.permission sp ON sp.node_path OPERATOR(ext.<@) p.node_path;

create or replace view auth.user_group_members
            (tenant_id, member_id, tenant_code, user_id, user_display_name, user_uuid, user_code, user_group_id, is_external, is_active, is_assignable,
             group_title, group_code, member_type, member_type_code, mapped_object_name, mapped_role)
as
SELECT ug.tenant_id,
    ugm.member_id,
        CASE
            WHEN t.code IS NULL THEN 'system'::text
            ELSE t.code
        END AS tenant_code,
    ui.user_id,
    ui.display_name AS user_display_name,
    ui.uuid AS user_uuid,
    ui.code AS user_code,
    ug.user_group_id,
    ug.is_external,
    ug.is_active,
    ug.is_assignable,
    ug.title AS group_title,
    ug.code AS group_code,
        CASE
            WHEN ugm.mapping_id IS NOT NULL THEN 'mapped_member'::text
            ELSE 'direct_member'::text
        END AS member_type,
    ugm.member_type_code,
    u.mapped_object_name,
    u.mapped_role
   FROM auth.user_group ug
     LEFT JOIN auth.user_group_member ugm ON ugm.user_group_id = ug.user_group_id
     LEFT JOIN auth.user_info ui ON ui.user_id = ugm.user_id
     JOIN auth.tenant t ON ug.tenant_id = t.tenant_id
     LEFT JOIN auth.user_group_mapping u ON ugm.mapping_id = u.user_group_mapping_id;


-- =============================================================================
-- Notification resolution views
-- =============================================================================
-- These views are used by the backend after receiving a pg_notify notification
-- to resolve which user_ids are affected and need to be notified via SSE/WebSocket.
--
-- Usage: backend receives notification with target_type + target_id,
-- then queries the matching view with WHERE target_id = <id> to get affected user_ids.
-- For target_type = 'user', no view is needed — user_id is already in the payload.

-- group_id → affected user_ids
-- Used for: group_member_added/removed, group_disabled/enabled, group_deleted,
--           group_type_changed, group_mapping_created/deleted,
--           permission_assigned/unassigned (to group)
create or replace view auth.notify_group_users
            (user_group_id, tenant_id, user_id) as
select ugm.user_group_id,
       ug.tenant_id,
       ugm.user_id
from auth.user_group_member ugm
         inner join auth.user_group ug on ug.user_group_id = ugm.user_group_id;

-- perm_set_id → affected user_ids
-- Used for: perm_set_permissions_added/removed, perm_set_updated
-- Resolves both direct user assignments and group member assignments
create or replace view auth.notify_perm_set_users
            (perm_set_id, tenant_id, user_id) as
-- Users with this perm_set directly assigned
select pa.perm_set_id,
       pa.tenant_id,
       pa.user_id
from auth.permission_assignment pa
where pa.perm_set_id is not null
  and pa.user_id is not null

union

-- Users in groups that have this perm_set assigned
select pa.perm_set_id,
       pa.tenant_id,
       ugm.user_id
from auth.permission_assignment pa
         inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id
where pa.perm_set_id is not null;

-- permission_id → affected user_ids
-- Used for: permission_assignability_changed
-- Resolves through: direct assignment, perm_set membership, and group membership
create or replace view auth.notify_permission_users
            (permission_id, user_id) as
-- Users with this permission directly assigned
select pa.permission_id,
       pa.user_id
from auth.permission_assignment pa
where pa.permission_id is not null
  and pa.user_id is not null

union

-- Users in groups with this permission directly assigned
select pa.permission_id,
       ugm.user_id
from auth.permission_assignment pa
         inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id
where pa.permission_id is not null

union

-- Users with this permission via perm_set (direct assignment)
select psp.permission_id,
       pa.user_id
from auth.perm_set_perm psp
         inner join auth.permission_assignment pa on pa.perm_set_id = psp.perm_set_id
where pa.user_id is not null

union

-- Users with this permission via perm_set (group assignment)
select psp.permission_id,
       ugm.user_id
from auth.perm_set_perm psp
         inner join auth.permission_assignment pa on pa.perm_set_id = psp.perm_set_id
         inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id;

-- provider_code → affected user_ids
-- Used for: provider_disabled, provider_deleted
create or replace view auth.notify_provider_users
            (provider_code, user_id) as
select ui.provider_code,
       ui.user_id
from auth.user_identity ui
where ui.is_active;

-- tenant_id → affected user_ids
-- Used for: tenant_deleted
create or replace view auth.notify_tenant_users
            (tenant_id, user_id) as
select tu.tenant_id,
       tu.user_id
from auth.tenant_user tu;

