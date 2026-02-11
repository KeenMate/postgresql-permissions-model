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
            (perm_set_id, perm_set_code, perm_set_title, perm_set_is_assignable, permission_id, permission_title, permission_code, permission_is_assignable) as
SELECT DISTINCT ps.perm_set_id,
    ps.code AS perm_set_code,
    ps.title AS perm_set_title,
    ps.is_assignable AS perm_set_is_assignable,
    sp.permission_id,
    sp.title AS permission_title,
    sp.full_code AS permission_code,
    sp.is_assignable AS permission_is_assignable
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
     LEFT JOIN auth.user_group_member ugm ON ugm.group_id = ug.user_group_id
     LEFT JOIN auth.user_info ui ON ui.user_id = ugm.user_id
     JOIN auth.tenant t ON ug.tenant_id = t.tenant_id
     LEFT JOIN auth.user_group_mapping u ON ugm.mapping_id = u.ug_mapping_id;

