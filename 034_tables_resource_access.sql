/*
 * Resource Access (ACL) Tables
 * ============================
 *
 * Lookup tables, partitioned ACL table, indexes, and partition helper
 * for resource-based authorization.
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

/*
 * const.resource_type — Registry of valid resource types
 */
create table const.resource_type
(
    code        text    not null primary key,
    title       text    not null,
    description text,
    is_active   boolean not null default true,
    source      text    default null
);

/*
 * const.resource_access_flag — Valid access flags
 */
create table const.resource_access_flag
(
    code   text not null primary key,
    title  text not null,
    source text default null
);

insert into const.resource_access_flag (code, title, source) values
    ('read',   'Read',   'core'),
    ('write',  'Write',  'core'),
    ('delete', 'Delete', 'core'),
    ('share',  'Share',  'core')
on conflict do nothing;

/*
 * auth.resource_access — Partitioned ACL table
 *
 * One row = one flag for one user/group on one resource.
 * A user can have multiple rows per resource (one per flag).
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
    resource_id        bigint      not null,
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
    primary key (resource_access_id, resource_type)
) partition by list (resource_type);

-- Default partition (catches unregistered types)
create table auth.resource_access_default
    partition of auth.resource_access default;

/*
 * Indexes
 */

-- Primary lookup: "does user X have flag Y on resource Z?"
create unique index uq_ra_user_flag
    on auth.resource_access (resource_type, tenant_id, resource_id, user_id, access_flag)
    where user_id is not null;

create unique index uq_ra_group_flag
    on auth.resource_access (resource_type, tenant_id, resource_id, user_group_id, access_flag)
    where user_group_id is not null;

-- Reverse: "what resources can user X access?"
create index ix_ra_user_resources
    on auth.resource_access (resource_type, tenant_id, user_id)
    where user_id is not null;

-- Reverse: "what resources can group X access?"
create index ix_ra_group_resources
    on auth.resource_access (resource_type, tenant_id, user_group_id)
    where user_group_id is not null;

-- "Who has access to resource Y?"
create index ix_ra_resource_grants
    on auth.resource_access (resource_type, tenant_id, resource_id);

/*
 * Partition helper — creates a partition for a resource type if it doesn't exist
 */
create or replace function unsecure.ensure_resource_access_partition(_resource_type text)
returns void language plpgsql as $$
declare
    _partition_name text;
begin
    _partition_name := 'resource_access_' || replace(_resource_type, '.', '_');
    if not exists (
        select 1 from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'auth' and c.relname = _partition_name
    ) then
        execute format(
            'create table auth.%I partition of auth.resource_access for values in (%L)',
            _partition_name, _resource_type
        );
    end if;
end;
$$;
