/*
 * Resource Access (ACL) Functions
 * ================================
 *
 * Functions for resource-based authorization:
 * - auth.has_resource_access          — single resource check (with hierarchy walk-up)
 * - auth.filter_accessible_resources  — bulk filter (with hierarchy walk-up)
 * - auth.get_resource_access_flags    — effective flags for a user on a resource
 * - auth.get_resource_access_matrix   — full sub-type × flag matrix for UI
 * - auth.grant_resource_access        — grant flags to user/group
 * - auth.deny_resource_access         — deny flags for a user (overrides group grants)
 * - auth.revoke_resource_access       — revoke specific flags
 * - auth.revoke_all_resource_access   — revoke all flags for a resource
 * - auth.get_resource_grants          — list all grants/denies for a resource
 * - auth.get_user_accessible_resources — list resources a user can access
 * - auth.create_resource_type         — register a new resource type (with hierarchy)
 * - auth.update_resource_type         — update resource type title/description/active/source
 * - auth.ensure_resource_types        — bulk-ensure resource types from JSONB array
 * - auth.get_resource_types           — list registered resource types
 * - auth.ensure_access_flags          — bulk-ensure global access flags
 * - auth.ensure_resource_type_flags   — ensure per-type flag mappings (add/remove to match)
 * - auth.get_access_flags             — list all global access flags
 *
 * v3: resource_id is jsonb (composite key).
 *     Containment queries (@>) for matching.
 *     Key schema validation at grant/deny time.
 *     filter_accessible_resources accepts jsonb[] instead of bigint[].
 *
 * Note: Read-path functions (has_resource_access, filter_accessible_resources, etc.)
 * are NOT marked STABLE because they call unsecure.get_cached_group_ids() which
 * performs INSERT/UPDATE on auth.user_group_id_cache on cache miss.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Validation helpers (unsecure)
-- ============================================================================

create or replace function unsecure.validate_resource_type(_resource_type text)
returns void
    language plpgsql
as
$$
begin
    if not exists (
        select 1 from const.resource_type
        where code = _resource_type and is_active = true
    ) then
        perform error.raise_35003(_resource_type);
    end if;
end;
$$;

create or replace function unsecure.validate_access_flags(_access_flags text[])
returns void
    language plpgsql
as
$$
declare
    _flag text;
begin
    foreach _flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_access_flag where code = _flag
        ) then
            perform error.raise_35004(_flag);
        end if;
    end loop;
end;
$$;

/*
 * unsecure.validate_access_flags_for_type — Validates flags against per-type mapping
 *
 * If the resource type has entries in const.resource_type_flag, only those flags
 * are allowed. If no entries exist, all flags are permitted (backward compat).
 * Throws error 35006 for invalid flags.
 */
create or replace function unsecure.validate_access_flags_for_type(_resource_type text, _access_flags text[])
returns void
    language plpgsql
as
$$
declare
    _flag text;
    _has_type_flags boolean;
begin
    -- Check if this resource type has any flag mappings
    select exists(
        select 1 from const.resource_type_flag where resource_type_code = _resource_type
    ) into _has_type_flags;

    -- No mappings → all flags allowed (backward compat)
    if not _has_type_flags then
        return;
    end if;

    -- Validate each flag against the type's allowed flags
    foreach _flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_type_flag
            where resource_type_code = _resource_type and access_flag_code = _flag
        ) then
            raise exception 'Access flag "%" is not valid for resource type "%"', _flag, _resource_type
                using errcode = '35006';
        end if;
    end loop;
end;
$$;

-- ============================================================================
-- Core check: auth.has_resource_access
-- ============================================================================
--
-- Deny-overrides algorithm with hierarchy walk-up:
-- 1. System user (id=1) → true
-- 2. Tenant owner → true
-- 3. Get cached group IDs
-- 4. Walk up the type hierarchy (most specific first):
--    a. User-level DENY → false
--    b. User-level GRANT → true
--    c. Group-level GRANT (via cached group IDs) → true
-- 5. No grant found → false (or throw error)
--
-- resource_id is jsonb. Matching uses containment (@>):
--   A grant on {"project_id": 42} matches checks for
--   {"project_id": 42, "folder_id": 100} at ancestor type level.
--
create or replace function auth.has_resource_access(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _required_flag  text default 'read',
    _tenant_id      integer default 1,
    _throw_err      boolean default true
) returns boolean
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor         record;
    _ancestor_key     jsonb;
begin
    -- System user bypasses all checks
    if _user_id = 1 then
        return true;
    end if;

    -- Tenant owner bypasses all checks
    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return true;
    end if;

    -- Get cached group IDs for this user/tenant
    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);

    -- Root type for partition pruning
    _root_type := split_part(_resource_type, '.', 1);

    -- Walk up the type hierarchy (most specific first)
    for _ancestor in
        select rt.code, rt.key_schema
        from const.resource_type rt
        where rt.path @> (select path from const.resource_type where code = _resource_type)
          and rt.is_active = true
        order by nlevel(rt.path) desc
    loop
        -- Build the ancestor key by extracting only fields from ancestor's schema
        -- e.g., for 'project' ancestor checking 'project.documents' resource_id:
        --   resource_id = {"project_id": 42, "folder_id": 100}
        --   ancestor key_schema = {"project_id": "bigint"}
        --   ancestor_key = {"project_id": 42}
        if _ancestor.key_schema is not null and _ancestor.key_schema <> '{}'::jsonb then
            select jsonb_object_agg(k, _resource_id->k)
            from jsonb_object_keys(_ancestor.key_schema) as k
            where _resource_id ? k
            into _ancestor_key;
        else
            _ancestor_key := _resource_id;
        end if;

        if _ancestor_key is null then
            continue;
        end if;

        -- User-level DENY overrides everything
        if exists (
            select 1 from auth.resource_access
            where root_type = _root_type
              and resource_type = _ancestor.code
              and tenant_id = _tenant_id
              and resource_id = _ancestor_key
              and user_id = _user_id
              and access_flag = _required_flag
              and is_deny = true
        ) then
            if _throw_err then
                perform error.raise_35001(_user_id, _resource_type, _resource_id, _tenant_id);
            end if;
            return false;
        end if;

        -- User-level GRANT
        if exists (
            select 1 from auth.resource_access
            where root_type = _root_type
              and resource_type = _ancestor.code
              and tenant_id = _tenant_id
              and resource_id = _ancestor_key
              and user_id = _user_id
              and access_flag = _required_flag
              and is_deny = false
        ) then
            return true;
        end if;

        -- Group-level GRANT (via cached group IDs)
        if exists (
            select 1 from auth.resource_access
            where root_type = _root_type
              and resource_type = _ancestor.code
              and tenant_id = _tenant_id
              and resource_id = _ancestor_key
              and user_group_id = any(_cached_group_ids)
              and access_flag = _required_flag
              and is_deny = false
        ) then
            return true;
        end if;
    end loop;

    -- No grant found
    if _throw_err then
        perform error.raise_35001(_user_id, _resource_type, _resource_id, _tenant_id);
    end if;

    return false;
end;
$$;

-- ============================================================================
-- Bulk check: auth.filter_accessible_resources
-- ============================================================================
--
-- Returns which resource_ids from a given array the user can access
-- (with a given flag). Respects deny-overrides and hierarchy walk-up.
--
-- resource_ids is jsonb[] (array of jsonb composite keys).
--
create or replace function auth.filter_accessible_resources(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_ids   jsonb[],
    _required_flag  text default 'read',
    _tenant_id      integer default 1
) returns table(__resource_id jsonb)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
    -- System user sees everything
    if _user_id = 1 then
        return query select unnest(_resource_ids);
        return;
    end if;

    -- Tenant owner sees everything
    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return query select unnest(_resource_ids);
        return;
    end if;

    -- Get cached group IDs
    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);

    -- Root type for partition pruning
    _root_type := split_part(_resource_type, '.', 1);

    -- Get all ancestor types (including self)
    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    return query
    select r.id
    from unnest(_resource_ids) as r(id)
    where
        -- Not denied at user level (at any ancestor level)
        not exists (
            select 1 from auth.resource_access
            where root_type = _root_type
              and resource_type = any(_ancestor_types)
              and tenant_id = _tenant_id
              and resource_id @> r.id
              and user_id = _user_id
              and access_flag = _required_flag
              and is_deny = true
        )
        and (
            -- User-level GRANT (at any ancestor level)
            exists (
                select 1 from auth.resource_access
                where root_type = _root_type
                  and resource_type = any(_ancestor_types)
                  and tenant_id = _tenant_id
                  and resource_id @> r.id
                  and user_id = _user_id
                  and access_flag = _required_flag
                  and is_deny = false
            )
            or
            -- Group-level GRANT (via cached group IDs, at any ancestor level)
            exists (
                select 1 from auth.resource_access
                where root_type = _root_type
                  and resource_type = any(_ancestor_types)
                  and tenant_id = _tenant_id
                  and resource_id @> r.id
                  and user_group_id = any(_cached_group_ids)
                  and access_flag = _required_flag
                  and is_deny = false
            )
        );
end;
$$;

-- ============================================================================
-- Get effective flags: auth.get_resource_access_flags
-- ============================================================================
--
-- Returns all effective flags a user has on a specific resource
-- (after deny resolution). __source = 'direct', 'owner', 'system', or group title.
-- Includes inherited flags from ancestor types.
--
create or replace function auth.get_resource_access_flags(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1
) returns table(__access_flag text, __source text)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
    -- System user gets all flags
    if _user_id = 1 then
        return query
            select raf.code, 'system'::text
            from const.resource_access_flag raf;
        return;
    end if;

    -- Tenant owner gets all flags
    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return query
            select raf.code, 'owner'::text
            from const.resource_access_flag raf;
        return;
    end if;

    -- Get cached group IDs
    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);

    -- Root type for partition pruning
    _root_type := split_part(_resource_type, '.', 1);

    -- Get all ancestor types (including self)
    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    return query
    with denied_flags as (
        -- Collect user-level denies across all ancestor types
        select ra.access_flag
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_id = _user_id
          and ra.is_deny = true
    ),
    direct_grants as (
        -- User-level grants not denied, across all ancestor types
        select distinct ra.access_flag, 'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_id = _user_id
          and ra.is_deny = false
          and ra.access_flag not in (select df.access_flag from denied_flags df)
    ),
    group_grants as (
        -- Group-level grants not denied, via cached group IDs
        select distinct on (ra.access_flag) ra.access_flag, ug.title as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_group_id = any(_cached_group_ids)
          and ra.is_deny = false
          and ra.access_flag not in (select df.access_flag from denied_flags df)
          and ra.access_flag not in (select dg.access_flag from direct_grants dg)
        order by ra.access_flag, ug.title
    )
    select * from direct_grants
    union all
    select * from group_grants;
end;
$$;

-- ============================================================================
-- Permission matrix: auth.get_resource_access_matrix
-- ============================================================================
--
-- Returns the full sub-type × flag matrix for a resource in one call.
-- Used by the frontend to build permission UIs (buttons/tabs/cards).
--
-- Given a root or parent type (e.g. 'project'), returns:
-- - All descendant types and their flags
-- - Includes inherited flags (grant on parent cascades to children)
-- - Respects deny-overrides (including denies on ancestor types)
--
create or replace function auth.get_resource_access_matrix(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1
) returns table(
    __resource_type text,
    __access_flag   text,
    __source        text
)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _is_owner         boolean;
begin
    -- System user gets all valid flags on all descendant types
    if _user_id = 1 then
        return query
            select rt.code, raf.code, 'system'::text
            from const.resource_type rt
            cross join const.resource_access_flag raf
            where rt.path <@ (select path from const.resource_type where code = _resource_type)
              and rt.is_active = true
              -- Only flags valid for this type (or all if no per-type mapping)
              and (not exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
                   or exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code and rtf.access_flag_code = raf.code));
        return;
    end if;

    -- Tenant owner gets all valid flags on all descendant types
    _is_owner := auth.is_owner(_user_id, _correlation_id, null, _tenant_id);
    if _is_owner then
        return query
            select rt.code, raf.code, 'owner'::text
            from const.resource_type rt
            cross join const.resource_access_flag raf
            where rt.path <@ (select path from const.resource_type where code = _resource_type)
              and rt.is_active = true
              and (not exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
                   or exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code and rtf.access_flag_code = raf.code));
        return;
    end if;

    -- Get cached group IDs
    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);

    -- Root type for partition pruning
    _root_type := split_part(_resource_type, '.', 1);

    return query
    with descendant_types as (
        -- All types under _resource_type (including self)
        select rt.code, rt.path
        from const.resource_type rt
        where rt.path <@ (select path from const.resource_type where code = _resource_type)
          and rt.is_active = true
    ),
    denied_flags as (
        -- User-level denies at any level in the subtree for this resource
        select ra.resource_type, ra.access_flag
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_id = _user_id
          and ra.is_deny = true
          and ra.resource_type in (select dt.code from descendant_types dt)
    ),
    direct_grants as (
        -- User-level grants on this resource within the subtree
        select ra.resource_type, ra.access_flag, 'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_id = _user_id
          and ra.is_deny = false
          and ra.resource_type in (select dt.code from descendant_types dt)
    ),
    group_grants as (
        -- Group-level grants on this resource (via cached group IDs)
        select distinct on (ra.resource_type, ra.access_flag)
            ra.resource_type, ra.access_flag, ug.title as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and ra.resource_id @> _resource_id
          and ra.user_group_id = any(_cached_group_ids)
          and ra.is_deny = false
          and ra.resource_type in (select dt.code from descendant_types dt)
        order by ra.resource_type, ra.access_flag, ug.title
    ),
    all_grants as (
        -- Combine direct + group grants (direct takes priority)
        select dg.resource_type, dg.access_flag, dg.source from direct_grants dg
        union all
        select gg.resource_type, gg.access_flag, gg.source from group_grants gg
        where not exists (
            select 1 from direct_grants dg2
            where dg2.resource_type = gg.resource_type
              and dg2.access_flag = gg.access_flag
        )
    ),
    explicit_grants as (
        -- Filter out denied flags (deny on a specific type blocks that type)
        select ag.resource_type, ag.access_flag, ag.source
        from all_grants ag
        where not exists (
            select 1 from denied_flags df
            where df.resource_type = ag.resource_type
              and df.access_flag = ag.access_flag
        )
    ),
    -- Inheritance: a grant on a parent type cascades to all children
    -- unless the child has an explicit deny or already has an explicit grant
    inherited_grants as (
        select dt.code as resource_type, eg.access_flag, eg.source
        from explicit_grants eg
        inner join const.resource_type parent_rt on parent_rt.code = eg.resource_type
        inner join descendant_types dt on dt.path <@ parent_rt.path and dt.code <> eg.resource_type
        where not exists (
            -- Don't inherit if child has an explicit deny
            select 1 from denied_flags df
            where df.resource_type = dt.code
              and df.access_flag = eg.access_flag
        )
        and not exists (
            -- Don't duplicate if child already has an explicit grant
            select 1 from explicit_grants eg2
            where eg2.resource_type = dt.code
              and eg2.access_flag = eg.access_flag
        )
    )
    select eg.resource_type, eg.access_flag, eg.source from explicit_grants eg
    union all
    select ig.resource_type, ig.access_flag, ig.source from inherited_grants ig;
end;
$$;

-- ============================================================================
-- Grant: auth.grant_resource_access
-- ============================================================================
--
-- Grant one or more flags to a user or group.
-- UPSERT: if exists as deny, flips is_deny to false.
-- resource_id is jsonb — validated against key_schema.
--
create or replace function auth.grant_resource_access(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _target_user_id bigint default null,
    _user_group_id  integer default null,
    _access_flags   text[] default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
    language plpgsql
as
$$
declare
    _flag text;
    __last_id bigint;
    _target_type text;
    _target_name text;
    _root_type text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.grant_access', _tenant_id);

    -- Validate target
    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    -- Validate resource type, flags (global + per-type), and resource_id key schema
    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_access_flags(_access_flags);
    perform unsecure.validate_access_flags_for_type(_resource_type, _access_flags);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    -- Compute root type
    _root_type := split_part(_resource_type, '.', 1);

    -- Determine target info for journaling
    if _target_user_id is not null then
        _target_type := 'user';
        select coalesce(display_name, code, user_id::text)
        from auth.user_info where user_id = _target_user_id
        into _target_name;
    else
        _target_type := 'group';
        select coalesce(title, code, user_group_id::text)
        from auth.user_group where user_group_id = _user_group_id
        into _target_name;
    end if;

    foreach _flag in array _access_flags
    loop
        __last_id := null;

        -- Check if row already exists (exact match on resource_id jsonb)
        if _target_user_id is not null then
            select ra.resource_access_id from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = _resource_type
              and ra.tenant_id = _tenant_id
              and ra.resource_id = _resource_id
              and ra.user_id = _target_user_id
              and ra.access_flag = _flag
            into __last_id;
        else
            select ra.resource_access_id from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = _resource_type
              and ra.tenant_id = _tenant_id
              and ra.resource_id = _resource_id
              and ra.user_group_id = _user_group_id
              and ra.access_flag = _flag
            into __last_id;
        end if;

        if __last_id is not null then
            -- Row exists — flip to grant if it was a deny
            update auth.resource_access
            set is_deny = false,
                updated_by = _created_by,
                updated_at = now(),
                granted_by = _user_id
            where resource_access_id = __last_id
              and root_type = _root_type;
        else
            -- Insert new grant
            insert into auth.resource_access (
                created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
                user_id, user_group_id, access_flag, is_deny, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, _root_type, _resource_id,
                _target_user_id, _user_group_id, _flag, false, _user_id
            )
            returning resource_access_id into __last_id;
        end if;

        return query select __last_id, _flag;
    end loop;

    -- Journal
    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18010  -- resource_access_granted
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'target_type', _target_type, 'target_name', _target_name,
            'access_flags', _access_flags)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- Deny: auth.deny_resource_access
-- ============================================================================
--
-- Deny one or more flags for a user (overrides group grants).
-- User-level only, deny on groups not supported.
--
create or replace function auth.deny_resource_access(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _target_user_id bigint,
    _access_flags   text[] default array['read'],
    _tenant_id      integer default 1
) returns table(__resource_access_id bigint, __access_flag text)
    language plpgsql
as
$$
declare
    _flag text;
    __last_id bigint;
    _target_name text;
    _root_type text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.deny_access', _tenant_id);

    -- Validate resource type, flags (global + per-type), and resource_id key schema
    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_access_flags(_access_flags);
    perform unsecure.validate_access_flags_for_type(_resource_type, _access_flags);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    -- Compute root type
    _root_type := split_part(_resource_type, '.', 1);

    select coalesce(display_name, code, user_id::text)
    from auth.user_info where user_id = _target_user_id
    into _target_name;

    foreach _flag in array _access_flags
    loop
        -- Check if a grant row already exists for this user+flag
        select ra.resource_access_id from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = _resource_type
          and ra.tenant_id = _tenant_id
          and ra.resource_id = _resource_id
          and ra.user_id = _target_user_id
          and ra.access_flag = _flag
        into __last_id;

        if __last_id is not null then
            -- Flip to deny
            update auth.resource_access
            set is_deny = true,
                updated_by = _created_by,
                updated_at = now(),
                granted_by = _user_id
            where resource_access_id = __last_id
              and root_type = _root_type;
        else
            -- Insert as deny
            insert into auth.resource_access (
                created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
                user_id, access_flag, is_deny, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, _root_type, _resource_id,
                _target_user_id, _flag, true, _user_id
            )
            returning resource_access_id into __last_id;
        end if;

        return query select __last_id, _flag;
    end loop;

    -- Journal
    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18012  -- resource_access_denied
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'target_type', 'user', 'target_name', _target_name,
            'access_flags', _access_flags)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- Revoke: auth.revoke_resource_access
-- ============================================================================
--
-- Revoke specific flags (removes rows entirely).
-- If _access_flags is null, revokes ALL flags.
--
create or replace function auth.revoke_resource_access(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _target_user_id bigint default null,
    _user_group_id  integer default null,
    _access_flags   text[] default null,
    _tenant_id      integer default 1
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count bigint;
    _target_type text;
    _target_name text;
    _root_type text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);

    -- Validate target
    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    -- Validate resource type
    perform unsecure.validate_resource_type(_resource_type);

    -- Validate flags if provided
    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    -- Compute root type
    _root_type := split_part(_resource_type, '.', 1);

    -- Determine target info for journaling
    if _target_user_id is not null then
        _target_type := 'user';
        select coalesce(display_name, code, user_id::text)
        from auth.user_info where user_id = _target_user_id
        into _target_name;
    else
        _target_type := 'group';
        select coalesce(title, code, user_group_id::text)
        from auth.user_group where user_group_id = _user_group_id
        into _target_name;
    end if;

    delete from auth.resource_access
    where root_type = _root_type
      and resource_type = _resource_type
      and tenant_id = _tenant_id
      and resource_id = _resource_id
      and (_target_user_id is null or user_id = _target_user_id)
      and (_user_group_id is null or user_group_id = _user_group_id)
      and (_access_flags is null or access_flag = any(_access_flags));

    get diagnostics __deleted_count = row_count;

    -- Journal
    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18011  -- resource_access_revoked
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'target_type', _target_type, 'target_name', _target_name,
            'access_flags', coalesce(_access_flags, array['*']),
            'deleted_count', __deleted_count)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- ============================================================================
-- Revoke all: auth.revoke_all_resource_access
-- ============================================================================
--
-- Revoke ALL access for a resource (cleanup when resource is deleted).
-- Uses containment (@>) so revoking 'project' with {"project_id": 42}
-- also removes child-type grants containing that project_id.
--
create or replace function auth.revoke_all_resource_access(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count bigint;
    _root_type text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);

    -- Validate resource type
    perform unsecure.validate_resource_type(_resource_type);

    -- Compute root type
    _root_type := split_part(_resource_type, '.', 1);

    -- Delete all grants/denies that contain this resource_id
    -- Uses @> so {"project_id": 42} matches {"project_id": 42, "folder_id": 100}
    delete from auth.resource_access
    where root_type = _root_type
      and tenant_id = _tenant_id
      and resource_id @> _resource_id;

    get diagnostics __deleted_count = row_count;

    -- Journal
    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18013  -- resource_access_bulk_revoked
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'deleted_count', __deleted_count)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- ============================================================================
-- Query: auth.get_resource_grants
-- ============================================================================
--
-- List all grants/denies for a specific resource.
--
create or replace function auth.get_resource_grants(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1
) returns table(
    __resource_access_id bigint,
    __user_id bigint,
    __user_display_name text,
    __user_group_id integer,
    __group_title text,
    __access_flag text,
    __is_deny boolean,
    __granted_by bigint,
    __granted_by_name text,
    __created_at timestamptz
)
    stable
    language plpgsql
as
$$
declare
    _root_type text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    _root_type := split_part(_resource_type, '.', 1);

    return query
    select
        ra.resource_access_id,
        ra.user_id,
        ui.display_name,
        ra.user_group_id,
        ug.title,
        ra.access_flag,
        ra.is_deny,
        ra.granted_by,
        gb.display_name,
        ra.created_at
    from auth.resource_access ra
    left join auth.user_info ui on ui.user_id = ra.user_id
    left join auth.user_group ug on ug.user_group_id = ra.user_group_id
    left join auth.user_info gb on gb.user_id = ra.granted_by
    where ra.root_type = _root_type
      and ra.resource_type = _resource_type
      and ra.tenant_id = _tenant_id
      and ra.resource_id = _resource_id
    order by ra.access_flag, ra.is_deny, ra.created_at;
end;
$$;

-- ============================================================================
-- Query: auth.get_user_accessible_resources
-- ============================================================================
--
-- List resources a user can access (with type and flag filter).
-- Self access is free, others require resources.get_grants.
--
create or replace function auth.get_user_accessible_resources(
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _resource_type   text,
    _access_flag     text default 'read',
    _tenant_id       integer default 1
) returns table(
    __resource_id jsonb,
    __access_flags text[],
    __source text
)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
    -- Self access is free, others require permission
    if _user_id <> _target_user_id then
        perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);
    end if;

    -- Get cached group IDs for the target user
    _cached_group_ids := unsecure.get_cached_group_ids(_target_user_id, _tenant_id);

    -- Root type for partition pruning
    _root_type := split_part(_resource_type, '.', 1);

    -- Get all ancestor types (including self)
    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    return query
    with denied_flags as (
        select ra.resource_id, ra.access_flag
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_id = _target_user_id
          and ra.is_deny = true
    ),
    direct_resources as (
        select ra.resource_id,
               array_agg(distinct ra.access_flag) as access_flags,
               'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_id = _target_user_id
          and ra.is_deny = false
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = ra.resource_id
                and df.access_flag = ra.access_flag
          )
          and (_access_flag is null or ra.access_flag = _access_flag)
        group by ra.resource_id
    ),
    group_resources as (
        select ra.resource_id,
               array_agg(distinct ra.access_flag) as access_flags,
               string_agg(distinct ug.title, ', ') as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_group_id = any(_cached_group_ids)
          and ra.is_deny = false
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = ra.resource_id
                and df.access_flag = ra.access_flag
          )
          and (_access_flag is null or ra.access_flag = _access_flag)
          -- Exclude resources already covered by direct grants
          and not exists (
              select 1 from direct_resources dr where dr.resource_id = ra.resource_id
          )
        group by ra.resource_id
    )
    select * from direct_resources
    union all
    select * from group_resources;
end;
$$;

-- ============================================================================
-- unsecure.update_resource_type_full_title
-- ============================================================================
-- Updates full_title for the given resource type and all its descendants.
-- Pattern matches unsecure.update_permission_full_title.
--
-- full_title = ancestor titles joined by ' > ', e.g.:
--   'project'            → 'Project'
--   'project.documents'  → 'Project > Project Documents'
--
create or replace function unsecure.update_resource_type_full_title(_path ext.ltree)
returns void
    language sql
as
$$
update const.resource_type rt
set full_title = (
    select array_to_string(
        array(
            select a.title
            from const.resource_type a
            where a.path @> s.path
            order by a.path
        ),
        ' > ')
    from const.resource_type s
    where s.code = rt.code
)
where rt.path <@ _path;
$$;

-- ============================================================================
-- Resource type management: auth.create_resource_type
-- ============================================================================
--
-- Register a new resource type and auto-create its partition.
-- Supports hierarchical types via _parent_code parameter.
--
-- Code convention: child type codes use dots to encode hierarchy:
--   Root: code='project'              path=ltree('project')
--   Child: code='project.documents'   path=ltree('project.documents')
--
-- The code IS the hierarchy — path is always text2ltree(code).
--
-- key_schema defines expected resource_id structure:
--   'project':           {"project_id": "bigint"}
--   'project.documents': {"project_id": "bigint", "folder_id": "bigint"}
--
create or replace function auth.create_resource_type(
    _created_by   text,
    _user_id      bigint,
    _correlation_id text,
    _code         text,
    _title        text,
    _parent_code  text default null,
    _description  text default null,
    _tenant_id    integer default 1,
    _source       text default null,
    _key_schema   jsonb default '{}'::jsonb,
    _access_flags text[] default null
) returns setof const.resource_type
    rows 1
    language plpgsql
as
$$
declare
    _path ext.ltree;
    _flag text;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    -- Validate parent exists if specified
    if _parent_code is not null then
        if not exists (
            select 1 from const.resource_type
            where code = _parent_code and is_active = true
        ) then
            perform error.raise_35003(_parent_code);
        end if;
    end if;

    -- Validate flags exist in global registry
    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    -- Path = text2ltree(code). The code itself encodes the hierarchy.
    _path := text2ltree(_code);

    -- Insert resource type (trigger updates full_title automatically)
    insert into const.resource_type (code, title, description, source, parent_code, path, key_schema)
    values (_code, _title, _description, _source, _parent_code, _path, coalesce(_key_schema, '{}'::jsonb))
    on conflict do nothing;

    -- Register per-type access flags
    if _access_flags is not null then
        foreach _flag in array _access_flags
        loop
            insert into const.resource_type_flag (resource_type_code, access_flag_code)
            values (_code, _flag)
            on conflict do nothing;
        end loop;
    end if;

    -- Auto-create partition (only for root types; children share the root partition)
    perform unsecure.ensure_resource_access_partition(_code);

    -- Return the created/existing row
    return query
        select * from const.resource_type rt where rt.code = _code;

    -- Journal (executes after return query in RETURNS SETOF functions)
    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18001  -- resource_type_created
        , 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title,
            'parent_code', _parent_code, 'key_schema', _key_schema,
            'access_flags', _access_flags)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- auth.update_resource_type
-- ============================================================================
-- Update an existing resource type's title, description, is_active, or source.
-- Code and parent_code are immutable (they define the hierarchy).
-- Trigger automatically recalculates full_title when title changes.
--
create or replace function auth.update_resource_type(
    _updated_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _title          text    default null,
    _description    text    default null,
    _is_active      boolean default null,
    _source         text    default null,
    _tenant_id      integer default 1
) returns setof const.resource_type
    rows 1
    language plpgsql
as
$$
begin
    -- Permission check (reuses create permission — admin-level operation)
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    -- Validate resource type exists
    if not exists (select 1 from const.resource_type where code = _code) then
        perform error.raise_35003(_code);
    end if;

    -- Update only non-null parameters
    update const.resource_type
    set title       = coalesce(_title, title),
        description = coalesce(_description, description),
        is_active   = coalesce(_is_active, is_active),
        source      = coalesce(_source, source)
    where code = _code;

    -- Return updated row
    return query
        select * from const.resource_type rt where rt.code = _code;

    -- Journal
    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18002  -- resource_type_updated
        , 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title,
            'is_active', _is_active)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- auth.ensure_resource_types
-- ============================================================================
-- Bulk-ensure resource types from a JSONB array.
--
-- Accepts an array of objects, each with:
--   code          (required) — resource type code, dots encode hierarchy
--   title         (required) — display title
--   parent_code   (optional) — parent resource type code
--   description   (optional) — description
--   source        (optional) — overrides the _source parameter per item
--   key_schema    (optional) — jsonb schema for resource_id validation
--   access_flags  (optional) — array of valid flag codes for this type
--
-- Items are automatically sorted by hierarchy depth (parents first),
-- so callers don't need to worry about ordering.
--
-- Example:
--   select * from auth.ensure_resource_types('app', 1, 'setup', '[
--       {"code": "project", "title": "Project",
--        "key_schema": {"project_id": "bigint"},
--        "access_flags": ["read", "write", "delete", "share"]},
--       {"code": "project.documents", "title": "Project Documents", "parent_code": "project",
--        "key_schema": {"project_id": "bigint", "folder_id": "bigint"},
--        "access_flags": ["read", "write", "delete", "export"]}
--   ]'::jsonb, _source := 'my_app');
--
create or replace function auth.ensure_resource_types(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_types jsonb,
    _source         text    default null,
    _tenant_id      integer default 1
) returns setof const.resource_type
    language plpgsql
as
$$
declare
    _item          jsonb;
    _code          text;
    _title         text;
    _parent_code   text;
    _description   text;
    _item_source   text;
    _key_schema    jsonb;
    _access_flags  text[];
    _flag          text;
    _path          ext.ltree;
begin
    -- Permission check (once for the batch)
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    -- Process items sorted by hierarchy depth (parents before children)
    for _item in
        select value
        from jsonb_array_elements(_resource_types)
        order by nlevel(text2ltree(value->>'code'))
    loop
        _code        := _item->>'code';
        _title       := _item->>'title';
        _parent_code := _item->>'parent_code';
        _description := _item->>'description';
        _item_source := coalesce(_item->>'source', _source);
        _key_schema  := coalesce(_item->'key_schema', '{}'::jsonb);
        _path        := text2ltree(_code);

        -- Parse access_flags from jsonb array to text[]
        if _item ? 'access_flags' and _item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(_item->'access_flags') as f(value)
            into _access_flags;
        else
            _access_flags := null;
        end if;

        -- Skip if already exists
        if exists (select 1 from const.resource_type where code = _code) then
            continue;
        end if;

        -- Validate parent exists if specified
        if _parent_code is not null then
            if not exists (
                select 1 from const.resource_type
                where code = _parent_code and is_active = true
            ) then
                perform error.raise_35003(_parent_code);
            end if;
        end if;

        -- Validate flags exist in global registry
        if _access_flags is not null then
            perform unsecure.validate_access_flags(_access_flags);
        end if;

        -- Insert (trigger updates full_title automatically)
        insert into const.resource_type (code, title, description, source, parent_code, path, key_schema)
        values (_code, _title, _description, _item_source, _parent_code, _path, _key_schema)
        on conflict do nothing;

        -- Register per-type access flags
        if _access_flags is not null then
            foreach _flag in array _access_flags
            loop
                insert into const.resource_type_flag (resource_type_code, access_flag_code)
                values (_code, _flag)
                on conflict do nothing;
            end loop;
        end if;

        -- Auto-create partition (only root types get a new partition)
        perform unsecure.ensure_resource_access_partition(_code);

        -- Journal
        perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18001  -- resource_type_created
            , 'resource_type', 0
            , jsonb_build_object('resource_type', _code, 'title', _title,
                'parent_code', _parent_code, 'key_schema', _key_schema,
                'access_flags', _access_flags)
            , _tenant_id);
    end loop;

    -- Return all processed resource types
    return query
        select rt.*
        from const.resource_type rt
        where rt.code in (select value->>'code' from jsonb_array_elements(_resource_types))
        order by rt.path;
end;
$$;

-- ============================================================================
-- auth.get_resource_types
-- ============================================================================
-- Lists registered resource types. No RBAC check — resource types are
-- public metadata (like access flags).
--
-- Optional filters:
--   _source      — filter by source (e.g. 'projects_app')
--   _parent_code — filter by parent (e.g. 'project' returns only children)
--   _active_only — if true (default), only active types are returned
--
create or replace function auth.get_resource_types(
    _source      text    default null,
    _parent_code text    default null,
    _active_only boolean default true
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __parent_code  text,
    __path         ext.ltree,
    __key_schema   jsonb,
    __access_flags text[]
)
    stable
    language plpgsql
as
$$
begin
    return query
    select rt.code, rt.title, rt.full_title, rt.description, rt.is_active, rt.source,
           rt.parent_code, rt.path, rt.key_schema,
           (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
            from const.resource_type_flag rtf
            where rtf.resource_type_code = rt.code)
    from const.resource_type rt
    where (_active_only = false or rt.is_active = true)
      and (_source is null or rt.source = _source)
      and (_parent_code is null or rt.parent_code = _parent_code)
    order by rt.path;
end;
$$;

-- ============================================================================
-- auth.ensure_access_flags
-- ============================================================================
-- Bulk-ensure global access flags exist in const.resource_access_flag.
-- Idempotent — existing flags are not modified.
--
-- Example:
--   select * from auth.ensure_access_flags('[
--       {"code": "comment", "title": "Comment"},
--       {"code": "subscribe", "title": "Subscribe"}
--   ]'::jsonb, _source := 'my_app');
--
create or replace function auth.ensure_access_flags(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _flags          jsonb,
    _source         text    default null,
    _tenant_id      integer default 1
) returns table(__code text, __title text, __source text)
    language plpgsql
as
$$
declare
    _item jsonb;
    _code text;
    _title text;
    _item_source text;
begin
    -- Permission check (same as create_resource_type — admin-level operation)
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for _item in select value from jsonb_array_elements(_flags)
    loop
        _code        := _item->>'code';
        _title       := _item->>'title';
        _item_source := coalesce(_item->>'source', _source);

        if _code is null or _title is null then
            raise exception 'Access flag requires both "code" and "title" fields'
                using errcode = '35004';
        end if;

        insert into const.resource_access_flag (code, title, source)
        values (_code, _title, _item_source)
        on conflict do nothing;
    end loop;

    return query
    select f.code, f.title, f.source
    from const.resource_access_flag f
    where f.code in (select value->>'code' from jsonb_array_elements(_flags))
    order by f.code;
end;
$$;

-- ============================================================================
-- auth.ensure_resource_type_flags
-- ============================================================================
-- Ensure a resource type has exactly the specified set of valid access flags.
--
-- Adds missing flags and removes flags not in the list. All flags must exist
-- in const.resource_access_flag (validated via unsecure.validate_access_flags).
--
-- Pass an empty array to remove all per-type mappings (allows all flags).
-- Pass null to leave existing mappings unchanged (no-op).
--
-- Example:
--   -- Set invoice to allow only read, write, approve
--   select * from auth.ensure_resource_type_flags('invoice', array['read', 'write', 'approve']);
--
--   -- Remove all mappings (revert to "all flags allowed")
--   select * from auth.ensure_resource_type_flags('invoice', array[]::text[]);
--
create or replace function auth.ensure_resource_type_flags(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _access_flags   text[],
    _tenant_id      integer default 1
) returns table(__resource_type_code text, __access_flag_code text)
    language plpgsql
as
$$
declare
    _flag text;
begin
    -- Permission check (same as create_resource_type — admin-level operation)
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    -- Null = no-op
    if _access_flags is null then
        return query
        select rtf.resource_type_code, rtf.access_flag_code
        from const.resource_type_flag rtf
        where rtf.resource_type_code = _resource_type
        order by rtf.access_flag_code;
        return;
    end if;

    -- Validate resource type exists
    if not exists (select 1 from const.resource_type where code = _resource_type) then
        perform error.raise_35003(_resource_type);
    end if;

    -- Validate all flags exist in global registry
    if array_length(_access_flags, 1) > 0 then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    -- Remove flags not in the new list
    delete from const.resource_type_flag
    where resource_type_code = _resource_type
      and access_flag_code != all(_access_flags);

    -- Add missing flags
    foreach _flag in array _access_flags
    loop
        insert into const.resource_type_flag (resource_type_code, access_flag_code)
        values (_resource_type, _flag)
        on conflict do nothing;
    end loop;

    return query
    select rtf.resource_type_code, rtf.access_flag_code
    from const.resource_type_flag rtf
    where rtf.resource_type_code = _resource_type
    order by rtf.access_flag_code;
end;
$$;

-- ============================================================================
-- auth.get_access_flags
-- ============================================================================
-- Lists all globally registered access flags.
-- No RBAC check — access flags are public metadata.
--
create or replace function auth.get_access_flags(
    _source text default null
) returns table(__code text, __title text, __source text)
    stable
    language plpgsql
as
$$
begin
    return query
    select f.code, f.title, f.source
    from const.resource_access_flag f
    where (_source is null or f.source = _source)
    order by f.code;
end;
$$;

-- ============================================================================
-- Trigger: const.resource_type → full_title
-- ============================================================================
-- Recalculate full_title on insert or when title/parent_code changes.
-- pg_trigger_depth() guard prevents recursion since the called function
-- updates full_title on the same table.
--
-- Placed here (not in 033_triggers) because it depends on both:
--   const.resource_type (034) and unsecure.update_resource_type_full_title (035)
--
create or replace function triggers.update_resource_type_full_title() returns trigger
    language plpgsql
as
$$
begin
    if pg_trigger_depth() > 1 then
        return new;
    end if;

    perform unsecure.update_resource_type_full_title(new.path);
    return new;
end;
$$;

create trigger trg_resource_type_full_title
    after insert or update of title, parent_code, full_title
    on const.resource_type
    for each row
execute function triggers.update_resource_type_full_title();
