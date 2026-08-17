/*
 * Resource Access (ACL) Tables
 * ============================
 *
 * Lookup tables, partitioned ACL table, indexes, and partition helper
 * for resource-based authorization.
 *
 * v3: resource_id is jsonb (composite key support).
 *     const.resource_type has key_schema defining expected key fields.
 *     Hierarchical resource types (ltree), root-type partitioning,
 *     and group membership cache table.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

/*
 * const.resource_type — Registry of valid resource types (hierarchical)
 *
 * Supports parent/child relationships for type inheritance via ltree path:
 *   'project'              → root type (path = 'project')
 *   'project.documents'    → child type (path = 'project.documents')
 *   'project.invoices'     → child type (path = 'project.invoices')
 *
 * A grant on 'project' cascades to all 'project.*' sub-types at check time.
 *
 * key_schema defines the expected resource_id jsonb structure:
 *   'project':           {"project_id": "bigint"}
 *   'project.documents': {"project_id": "bigint", "folder_id": "bigint"}
 *
 * Used for validation at grant/deny time and for documentation.
 */
create table const.resource_type
(
    code        text    not null primary key,
    is_active   boolean not null default true,
    source      text    default null,
    path        ext.ltree not null,
    key_schema  jsonb   not null default '{}'::jsonb
);

create index ix_resource_type_path on const.resource_type using gist (path);

/*
 * const.resource_access_flag — Valid access flags
 */
create table const.resource_access_flag
(
    code   text not null primary key,
    source text default null
);

insert into const.resource_access_flag (code, source) values
    ('read',    'core'),
    ('write',   'core'),
    ('delete',  'core'),
    ('share',   'core'),
    ('approve', 'core'),
    ('export',  'core')
on conflict do nothing;

-- Core flag translations are seeded in 046_seed_translations.sql

/*
 * const.resource_type_flag — Per-type access flag mapping
 *
 * Defines which access flags are valid for each resource type.
 * If a resource type has no entries here, ALL flags are allowed (backward compat).
 * When entries exist, only those flags can be used in grant/deny operations.
 *
 * Applications register their resource types with their valid flags on startup
 * via create_resource_type() or ensure_resource_types().
 */
create table const.resource_type_flag
(
    resource_type_code text not null references const.resource_type(code) on delete cascade,
    access_flag_code   text not null references const.resource_access_flag(code) on delete cascade,
    primary key (resource_type_code, access_flag_code)
);

/*
 * auth.resource_access — Partitioned ACL table (root-type partitioning)
 *
 * One row = one flag for one user/group on one resource.
 * A user can have multiple rows per resource (one per flag).
 *
 * resource_id is a jsonb composite key whose structure is defined by
 * the resource_type's key_schema.
 *
 * Examples:
 *   resource_type = 'project',           resource_id = {"project_id": 42}
 *   resource_type = 'project.documents', resource_id = {"project_id": 42, "folder_id": 100}
 *   resource_type = 'project.invoices',  resource_id = {"project_id": 42}
 *
 * Partitioned by root_type (first segment of resource_type):
 *   resource_type = 'project.documents' → root_type = 'project'
 *   All project.* sub-types share the 'resource_access_project' partition.
 */
create table auth.resource_access
(
    created_at         timestamptz default now()           not null,
    created_by         text        default 'unknown'::text not null,
    updated_at         timestamptz default now()           not null,
    updated_by         text        default 'unknown'::text not null,
    resource_access_id bigint generated always as identity,
    tenant_id          integer     not null references auth.tenant on delete cascade,
    resource_type      text        not null references const.resource_type,
    root_type          text        not null,
    resource_id        jsonb       not null default '{}'::jsonb,
    resource_path      ext.ltree,
    user_id            bigint      references auth.user_info on delete cascade,
    user_group_id      integer     references auth.user_group on delete cascade,
    access_flag        text        not null references const.resource_access_flag,
    is_deny            boolean     not null default false,
    granted_by         bigint      references auth.user_info on delete set null,
    constraint ra_created_by_check check (length(created_by) <= 250),
    constraint ra_updated_by_check check (length(updated_by) <= 250),
    constraint ra_either_user_or_group
        check ((user_id is not null) or (user_group_id is not null)),
    constraint ra_not_both_user_and_group
        check (not (user_id is not null and user_group_id is not null)),
    constraint ra_resource_id_is_object
        check (jsonb_typeof(resource_id) = 'object'),
    constraint ra_path_or_id
        check (resource_path is not null or resource_id <> '{}'::jsonb),
    primary key (resource_access_id, root_type)
) partition by list (root_type);

-- Default partition (catches unregistered root types)
create table auth.resource_access_default
    partition of auth.resource_access default;

/*
 * Indexes
 *
 * All indexes include root_type for partition pruning + resource_type for specificity.
 * resource_id uses GIN for jsonb containment (@>) queries.
 */

-- GIN index for containment queries: "all grants where resource_id @> {"project_id": 42}"
create index ix_ra_resource_id
    on auth.resource_access using gin (resource_id);

-- GiST index for path-based ancestor walks: "_target_path <@ resource_path"
-- Partition pruning on root_type gives locality within a resource domain.
create index ix_ra_resource_path
    on auth.resource_access using gist (resource_path)
    where resource_path is not null;

-- Primary lookup for id-only rows: "does user X have flag Y on resource Z?"
-- With jsonb we cannot have a traditional unique btree index, so we use a
-- unique index on md5(resource_id::text). Scoped to rows without a path so
-- that md5('{}'::text) collisions across path rows don't conflict.
create unique index uq_ra_user_flag
    on auth.resource_access (root_type, resource_type, tenant_id, md5(resource_id::text), user_id, access_flag)
    where user_id is not null and resource_path is null;

create unique index uq_ra_group_flag
    on auth.resource_access (root_type, resource_type, tenant_id, md5(resource_id::text), user_group_id, access_flag)
    where user_group_id is not null and resource_path is null;

-- Uniqueness for path-bearing rows (path-only or hybrid)
create unique index uq_ra_user_flag_path
    on auth.resource_access (root_type, resource_type, tenant_id, resource_path, md5(resource_id::text), user_id, access_flag)
    where user_id is not null and resource_path is not null;

create unique index uq_ra_group_flag_path
    on auth.resource_access (root_type, resource_type, tenant_id, resource_path, md5(resource_id::text), user_group_id, access_flag)
    where user_group_id is not null and resource_path is not null;

-- Reverse: "what resources can user X access?"
create index ix_ra_user_resources
    on auth.resource_access (root_type, resource_type, tenant_id, user_id)
    where user_id is not null;

-- Reverse: "what resources can group X access?"
create index ix_ra_group_resources
    on auth.resource_access (root_type, resource_type, tenant_id, user_group_id)
    where user_group_id is not null;

-- "Who has access to resource Y?" — uses GIN on resource_id
-- Combined with root_type/resource_type btree filtering
create index ix_ra_resource_grants
    on auth.resource_access (root_type, resource_type, tenant_id);

-- ============================================================================
-- const.resource_role — Named bundles of flags scoped to a resource_type
-- ============================================================================
-- A "resource role" is a named bundle of access flags scoped to a single
-- resource_type. Roles replace the N-row flag grant with a single assignment
-- row that expands to flags at check time.
--   Analogy:  perm_set : permission  ::  resource_role : access_flag
-- A role is defined for ONE resource_type. Cascade to descendants happens via
-- the ltree walk-up in has_resource_access, not via lax FKs.
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

/*
 * Partition helper — creates partitions for a root resource type
 *
 * Root-type logic: only root types get their own partition.
 * Child types (e.g. 'project.documents') share the root partition ('project').
 *
 * auth.resource_access and auth.resource_role_assignment live in lockstep:
 * registering a new root type via create_resource_type() / ensure_resource_types()
 * auto-creates BOTH partitions because they both call this single helper.
 */
create or replace function unsecure.ensure_resource_access_partition(_resource_type text)
returns void language plpgsql as $$
declare
    __root_type      text;
    __ra_partition   text;
    __rra_partition  text;
begin
    __root_type := split_part(_resource_type, '.', 1);

    -- auth.resource_access_<root>
    __ra_partition := 'resource_access_' || __root_type;
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = __ra_partition
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_access for values in (%L)',
            __ra_partition, __root_type
        );
    end if;

    -- auth.resource_role_assignment_<root>
    __rra_partition := 'resource_role_assignment_' || __root_type;
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = __rra_partition
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_role_assignment for values in (%L)',
            __rra_partition, __root_type
        );
    end if;
end;
$$;

/*
 * unsecure.validate_resource_id — Validates resource_id against key_schema
 *
 * _resource_id may carry any subset of the schema's keys; unknown keys
 * are rejected. This lets grants and denies be scoped at any level of the
 * key hierarchy (e.g. {project_id: 42} on 'project.invoices' means
 * "all invoices under project 42") and read-time containment matching
 * resolves the cascade.
 *
 * Empty/null _resource_id is a path-only assertion and skips validation;
 * the resource_path is the identity.
 */
create or replace function unsecure.validate_resource_id(
    _resource_type text,
    _resource_id jsonb
)
returns void language plpgsql as $$
declare
    __schema jsonb;
    __key text;
begin
    -- Empty resource_id = "no composite-key assertion" (path-only grant)
    if _resource_id is null or _resource_id = '{}'::jsonb then
        return;
    end if;

    select key_schema from const.resource_type where code = _resource_type into __schema;

    -- No schema → no validation
    if __schema is null or __schema = '{}'::jsonb then
        return;
    end if;

    -- Reject any key not in the schema
    for __key in select jsonb_object_keys(_resource_id)
    loop
        if not (__schema ? __key) then
            raise exception 'resource_id key "%" is not part of key_schema for resource type "%"', __key, _resource_type
                using errcode = '35005';
        end if;
    end loop;
end;
$$;

/*
 * auth.user_group_id_cache — Cached group membership IDs
 *
 * Mirrors the pattern of auth.user_permission_cache:
 * - Populated on demand when resource access functions detect expired/missing cache
 * - Source: auth.user_group_member + auth.user_group (is_active only)
 * - TTL: Same sys_param timeout as permission cache (default 300s)
 * - Soft invalidation: UPDATE expiration_date = now() on group membership changes
 * - Hard invalidation: DELETE on user disable/lock/delete
 */
create table auth.user_group_id_cache
(
    created_at      timestamptz default now()           not null,
    created_by      text        default 'unknown'::text not null,
    updated_at      timestamptz default now()           not null,
    updated_by      text        default 'unknown'::text not null,
    cache_id        bigint generated always as identity primary key,
    user_id         bigint      not null references auth.user_info on delete cascade,
    tenant_id       integer     not null references auth.tenant,
    group_ids       integer[]   not null default '{}',
    expiration_date timestamptz not null,
    constraint ugic_created_by_check check (length(created_by) <= 250),
    constraint ugic_updated_by_check check (length(updated_by) <= 250)
);

create unique index uq_user_group_id_cache
    on auth.user_group_id_cache (user_id, tenant_id);
