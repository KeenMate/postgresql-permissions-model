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
    resource_id        jsonb       not null,
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

-- Primary lookup: "does user X have flag Y on resource Z?"
-- With jsonb we cannot have a traditional unique btree index, so we use
-- a unique index on (root_type, resource_type, tenant_id, md5(resource_id::text), user_id, access_flag)
-- md5 hash gives us a fixed-width key for uniqueness enforcement.
create unique index uq_ra_user_flag
    on auth.resource_access (root_type, resource_type, tenant_id, md5(resource_id::text), user_id, access_flag)
    where user_id is not null;

create unique index uq_ra_group_flag
    on auth.resource_access (root_type, resource_type, tenant_id, md5(resource_id::text), user_group_id, access_flag)
    where user_group_id is not null;

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

/*
 * Partition helper — creates a partition for a root resource type
 *
 * Root-type logic: only root types get their own partition.
 * Child types (e.g. 'project.documents') share the root partition ('project').
 */
create or replace function unsecure.ensure_resource_access_partition(_resource_type text)
returns void language plpgsql as $$
declare
    _root_type text;
    _partition_name text;
begin
    _root_type := split_part(_resource_type, '.', 1);
    _partition_name := 'resource_access_' || _root_type;
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = _partition_name
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_access for values in (%L)',
            _partition_name, _root_type
        );
    end if;
end;
$$;

/*
 * unsecure.validate_resource_id — Validates resource_id against key_schema
 *
 * Checks that all required keys from the resource_type's key_schema
 * are present in the resource_id jsonb.
 */
create or replace function unsecure.validate_resource_id(_resource_type text, _resource_id jsonb)
returns void language plpgsql as $$
declare
    _schema jsonb;
    _key text;
begin
    select key_schema from const.resource_type where code = _resource_type into _schema;

    -- No schema → no validation
    if _schema is null or _schema = '{}'::jsonb then
        return;
    end if;

    -- Check each required key is present
    for _key in select jsonb_object_keys(_schema)
    loop
        if not (_resource_id ? _key) then
            raise exception 'resource_id missing required key "%" for resource type "%"', _key, _resource_type
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
