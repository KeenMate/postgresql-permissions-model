/*
 * Resource Roles — Errors, Events, Partition Catch-up
 * ===================================================
 *
 * A "resource role" is a named bundle of access flags scoped to a single
 * resource_type. Roles replace the N-row flag grant with a single
 * assignment row that expands to flags at check time.
 *
 * Analogy:  perm_set : permission  ::  resource_role : access_flag
 *
 * The role TABLES (const.resource_role, const.resource_role_flag,
 * auth.resource_role_assignment) and the shared partition helper
 * (unsecure.ensure_resource_access_partition) live in
 * 034_tables_resource_access.sql, alongside auth.resource_access, so the
 * role-aware functions in 035_functions_resource_access.sql can reference
 * them. This file carries only the pieces that must run after the event and
 * translation tables exist (012, 030): error functions, event metadata,
 * and a retroactive partition catch-up for existing databases.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ----------------------------------------------------------------------------
-- Retroactive catch-up: create role_assignment partitions for existing types
-- ----------------------------------------------------------------------------
-- If this migration runs against a database where resource_access partitions
-- already exist (e.g. project, folder, document), we need matching
-- resource_role_assignment partitions. The helper (in 034) is idempotent, so
-- calling it with existing root types is safe. On a fresh build the type
-- registry is still empty here, so this is a no-op.
do $$
declare
    __root text;
begin
    for __root in
        select distinct split_part(code, '.', 1) from const.resource_type
    loop
        perform unsecure.ensure_resource_access_partition(__root);
    end loop;
end $$;

-- ============================================================================
-- Error functions (35007-35009)
-- ============================================================================

-- 35007: Resource role not found
create or replace function error.raise_35007(_role_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Resource role (code: %) does not exist or is not active', _role_code
        using errcode = '35007';
end;
$$;

-- 35008: Role flags not valid for resource type
create or replace function error.raise_35008(_role_code text, _resource_type text, _bad_flag text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Resource role (code: %) cannot include flag "%" — not valid for resource type "%"',
        _role_code, _bad_flag, _resource_type
        using errcode = '35008';
end;
$$;

-- 35009: Role resource_type mismatch at assignment
create or replace function error.raise_35009(_role_code text, _role_type text, _assignment_type text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Resource role (code: %) is defined for type "%" but was assigned on type "%"',
        _role_code, _role_type, _assignment_type
        using errcode = '35009';
end;
$$;

-- ============================================================================
-- Event codes (18003-18005, 18020-18021)
-- ============================================================================
insert into const.event_code (event_id, code, category_code, is_system, source) values
    (18003, 'resource_role_created',        'resource_event', true, 'core'),
    (18004, 'resource_role_updated',        'resource_event', true, 'core'),
    (18005, 'resource_role_deleted',        'resource_event', true, 'core'),
    (18020, 'resource_role_assigned',       'resource_event', true, 'core'),
    (18021, 'resource_role_revoked',        'resource_event', true, 'core')
on conflict do nothing;

insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    ('system', 'system', 'en', 'event_code', 'resource_role_created', 'title', 'Resource Role Created'),
    ('system', 'system', 'en', 'event_code', 'resource_role_created', 'description', 'New resource role was registered'),
    ('system', 'system', 'en', 'event_code', 'resource_role_updated', 'title', 'Resource Role Updated'),
    ('system', 'system', 'en', 'event_code', 'resource_role_updated', 'description', 'Resource role definition or flags changed'),
    ('system', 'system', 'en', 'event_code', 'resource_role_deleted', 'title', 'Resource Role Deleted'),
    ('system', 'system', 'en', 'event_code', 'resource_role_deleted', 'description', 'Resource role was deleted'),
    ('system', 'system', 'en', 'event_code', 'resource_role_assigned', 'title', 'Resource Role Assigned'),
    ('system', 'system', 'en', 'event_code', 'resource_role_assigned', 'description', 'Resource role assigned to user or group'),
    ('system', 'system', 'en', 'event_code', 'resource_role_revoked', 'title', 'Resource Role Revoked'),
    ('system', 'system', 'en', 'event_code', 'resource_role_revoked', 'description', 'Resource role revoked from user or group')
on conflict do nothing;

-- Event message templates (en)
insert into const.event_message (event_id, language_code, message_template) values
    (18003, 'en', 'Resource role "{role_code}" was created by {actor}'),
    (18004, 'en', 'Resource role "{role_code}" was updated by {actor}'),
    (18005, 'en', 'Resource role "{role_code}" was deleted by {actor}'),
    (18020, 'en', 'Role "{role_code}" on {resource_type} "{resource_id}" was assigned to {target_type} "{target_name}" by {actor}'),
    (18021, 'en', 'Role "{role_code}" on {resource_type} "{resource_id}" was revoked from {target_type} "{target_name}" by {actor}')
on conflict do nothing;
