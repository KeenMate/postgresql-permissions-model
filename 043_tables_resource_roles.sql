/*
 * Resource Roles — Tables, Indexes, Partition Helper, Errors, Events
 * ===================================================================
 *
 * A "resource role" is a named bundle of access flags scoped to a single
 * resource_type. Roles replace the N-row flag grant with a single
 * assignment row that expands to flags at check time.
 *
 * Analogy:  perm_set : permission  ::  resource_role : access_flag
 *
 * Layout:
 *   const.resource_role            — global registry (per resource_type)
 *   const.resource_role_flag       — junction table (role → flags)
 *   auth.resource_role_assignment  — tenant-scoped, partitioned by root_type
 *
 * Key rules:
 *   - A role is defined for ONE resource_type. Cascade to descendants
 *     happens via the ltree walk-up in has_resource_access, not via lax FKs.
 *   - Role assignments are grant-only. Denies remain flag-level in
 *     auth.resource_access so precedence rules stay unambiguous.
 *   - Direct flag grants in auth.resource_access and role assignments
 *     coexist per user/group/resource. They're independent rows in
 *     independent tables; has_resource_access unions them at check time.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- const.resource_role — Named bundles of flags scoped to a resource_type
-- ============================================================================
create table if not exists const.resource_role
(
    code          text    not null primary key,
    resource_type text    not null references const.resource_type(code) on delete cascade,
    is_active     boolean not null default true,
    source        text,
    -- Unique target for the composite FK from resource_role_assignment.
    -- code is already PK; this exposes (code, resource_type) as a matchable pair.
    constraint uq_resource_role_code_type unique (code, resource_type)
);

create index if not exists ix_resource_role_resource_type
    on const.resource_role (resource_type);

create index if not exists ix_resource_role_source
    on const.resource_role (source)
    where source is not null;

-- ============================================================================
-- const.resource_role_flag — Flags belonging to a role
-- ============================================================================
-- Redefining a role = delete + insert here. No cascade to assignments needed:
-- has_resource_access expands roles at check time, so every assigned user/group
-- picks up the new flag set on the very next call.
create table if not exists const.resource_role_flag
(
    resource_role_code text not null references const.resource_role(code) on delete cascade,
    access_flag_code   text not null references const.resource_access_flag(code) on delete cascade,
    primary key (resource_role_code, access_flag_code)
);

create index if not exists ix_resource_role_flag_flag
    on const.resource_role_flag (access_flag_code);

-- ============================================================================
-- auth.resource_role_assignment — Tenant-scoped, partitioned by root_type
-- ============================================================================
-- One row per (tenant, resource, user|group, role_code).
-- Role grants (grant-only; no is_deny column). Denies stay in resource_access.
create table if not exists auth.resource_role_assignment
(
    created_at                  timestamptz default now()           not null,
    created_by                  text        default 'unknown'::text not null,
    updated_at                  timestamptz default now()           not null,
    updated_by                  text        default 'unknown'::text not null,
    resource_role_assignment_id bigint generated always as identity,
    tenant_id                   integer     not null references auth.tenant on delete cascade,
    resource_type               text        not null references const.resource_type,
    root_type                   text        not null,
    resource_id                 jsonb       not null default '{}'::jsonb,
    resource_path               ext.ltree,
    user_id                     bigint      references auth.user_info on delete cascade,
    user_group_id               integer     references auth.user_group on delete cascade,
    role_code                   text        not null,
    granted_by                  bigint      references auth.user_info on delete set null,
    constraint rra_created_by_check check (length(created_by) <= 250),
    constraint rra_updated_by_check check (length(updated_by) <= 250),
    constraint rra_either_user_or_group
        check ((user_id is not null) or (user_group_id is not null)),
    constraint rra_not_both_user_and_group
        check (not (user_id is not null and user_group_id is not null)),
    constraint rra_resource_id_is_object
        check (jsonb_typeof(resource_id) = 'object'),
    constraint rra_path_or_id
        check (resource_path is not null or resource_id <> '{}'::jsonb),
    -- Composite FK: role must be defined for exactly this resource_type.
    -- Hierarchical cascade happens via check-time walk-up, not via FK laxity.
    constraint rra_role_type_match
        foreign key (role_code, resource_type)
            references const.resource_role (code, resource_type)
            on delete cascade,
    primary key (resource_role_assignment_id, root_type)
) partition by list (root_type);

-- Default partition (catches unregistered root types)
create table if not exists auth.resource_role_assignment_default
    partition of auth.resource_role_assignment default;

-- ----------------------------------------------------------------------------
-- Indexes (mirror auth.resource_access)
-- ----------------------------------------------------------------------------

-- GIN for containment queries: "all role assignments where resource_id @> {...}"
create index if not exists ix_rra_resource_id
    on auth.resource_role_assignment using gin (resource_id);

-- GiST for path-based ancestor walks
create index if not exists ix_rra_resource_path
    on auth.resource_role_assignment using gist (resource_path)
    where resource_path is not null;

-- Primary lookup for id-only rows: "does user X have role Y on resource Z?"
create unique index if not exists uq_rra_user_role
    on auth.resource_role_assignment
        (root_type, resource_type, tenant_id, md5(resource_id::text), user_id, role_code)
    where user_id is not null and resource_path is null;

create unique index if not exists uq_rra_group_role
    on auth.resource_role_assignment
        (root_type, resource_type, tenant_id, md5(resource_id::text), user_group_id, role_code)
    where user_group_id is not null and resource_path is null;

-- Uniqueness for path-bearing rows
create unique index if not exists uq_rra_user_role_path
    on auth.resource_role_assignment
        (root_type, resource_type, tenant_id, resource_path, md5(resource_id::text), user_id, role_code)
    where user_id is not null and resource_path is not null;

create unique index if not exists uq_rra_group_role_path
    on auth.resource_role_assignment
        (root_type, resource_type, tenant_id, resource_path, md5(resource_id::text), user_group_id, role_code)
    where user_group_id is not null and resource_path is not null;

-- Reverse: "what resources can user X access via roles?"
create index if not exists ix_rra_user_resources
    on auth.resource_role_assignment (root_type, resource_type, tenant_id, user_id)
    where user_id is not null;

-- Reverse: "what resources can group X access via roles?"
create index if not exists ix_rra_group_resources
    on auth.resource_role_assignment (root_type, resource_type, tenant_id, user_group_id)
    where user_group_id is not null;

-- "Who has a role on resource Y?" — combined with GIN on resource_id
create index if not exists ix_rra_resource_assignments
    on auth.resource_role_assignment (root_type, resource_type, tenant_id);

-- ============================================================================
-- Partition helper — extended to also create resource_role_assignment partition
-- ============================================================================
-- Both tables live in lockstep. Registering a new root resource type via
-- create_resource_type() / ensure_resource_types() auto-creates both partitions
-- because they both call this single helper.
create or replace function unsecure.ensure_resource_access_partition(_resource_type text)
returns void language plpgsql as $$
declare
    _root_type      text;
    _ra_partition   text;
    _rra_partition  text;
begin
    _root_type := split_part(_resource_type, '.', 1);

    -- auth.resource_access_<root>
    _ra_partition := 'resource_access_' || _root_type;
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = _ra_partition
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_access for values in (%L)',
            _ra_partition, _root_type
        );
    end if;

    -- auth.resource_role_assignment_<root>
    _rra_partition := 'resource_role_assignment_' || _root_type;
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = _rra_partition
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_role_assignment for values in (%L)',
            _rra_partition, _root_type
        );
    end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- Retroactive catch-up: create role_assignment partitions for existing types
-- ----------------------------------------------------------------------------
-- If this migration runs against a database where resource_access partitions
-- already exist (e.g. project, folder, document), we need matching
-- resource_role_assignment partitions. The helper is idempotent, so calling
-- it with existing root types is safe.
do $$
declare
    _root text;
begin
    for _root in
        select distinct split_part(code, '.', 1) from const.resource_type
    loop
        perform unsecure.ensure_resource_access_partition(_root);
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
