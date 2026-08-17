/*
 * Resource Access (ACL) Functions
 * ================================
 *
 * Functions for resource-based authorization:
 * - auth.has_resource_access          — single resource check (with hierarchy walk-up)
 * - auth.filter_accessible_resources  — bulk filter (with hierarchy walk-up)
 * - auth.get_resource_access_flags    — effective flags for a user on a resource
 * - auth.get_resource_access_matrix   — full sub-type × flag matrix for UI
 * - auth.assign_resource_access        — grant flags to user/group
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
    __flag text;
begin
    foreach __flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_access_flag where code = __flag
        ) then
            perform error.raise_35004(__flag);
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
    __flag text;
    __has_type_flags boolean;
begin
    -- Check if this resource type has any flag mappings
    select exists(
        select 1 from const.resource_type_flag where resource_type_code = _resource_type
    ) into __has_type_flags;

    -- No mappings → all flags allowed (backward compat)
    if not __has_type_flags then
        return;
    end if;

    -- Validate each flag against the type's allowed flags
    foreach __flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_type_flag
            where resource_type_code = _resource_type and access_flag_code = __flag
        ) then
            raise exception 'Access flag "%" is not valid for resource type "%"', __flag, _resource_type
                using errcode = '35006';
        end if;
    end loop;
end;
$$;

-- Asserts that at least one of _resource_id or _resource_path identifies a target.
-- Used by both write paths (so you can't grant access to nothing) and read paths
-- (so a malformed query fails loudly instead of silently returning false / true
-- for the system user). Raises 35005.
create or replace function unsecure.validate_resource_identifier(
    _resource_id   jsonb,
    _resource_path text
) returns void
    language plpgsql immutable
as
$$
begin
    if (_resource_id is null or _resource_id = '{}'::jsonb) and _resource_path is null then
        raise exception 'Either _resource_id (non-empty) or _resource_path must be provided'
            using errcode = '35010';
    end if;
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
--    a. User-level DENY     (resource_access)          → false
--    b. User-level GRANT    (resource_access)          → true
--    c. User role GRANT     (resource_role_assignment) → true
--    d. Group-level GRANT   (resource_access)          → true
--    e. Group role GRANT    (resource_role_assignment) → true
-- 5. No grant found → false (or throw error)
--
-- resource_id is jsonb; matching uses containment (@>). resource_path (ltree,
-- passed as text) enables path-addressed grants that cascade via <@ walks.
--
create or replace function auth.has_resource_access(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb   default '{}'::jsonb,
    _required_flag  text    default 'read',
    _tenant_id      integer default 1,
    _throw_err      boolean default true,
    _resource_path  text    default null
) returns boolean
    language plpgsql
as
$$
declare
    __cached_group_ids integer[];
    __root_type        text;
    __ancestor         record;
    __ancestor_key     jsonb;
    __resource_path_lt ext.ltree;
begin
    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    if _user_id = 1 then
        return true;
    end if;

    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return true;
    end if;

    __cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    __root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __resource_path_lt := ext.text2ltree(_resource_path);

    for __ancestor in
        select rt.code, rt.key_schema
        from const.resource_type rt
        where rt.path @> (select path from const.resource_type where code = _resource_type)
          and rt.is_active = true
        order by ext.nlevel(rt.path) desc
    loop
        -- Build the id-component lookup key for this ancestor
        if __ancestor.key_schema is not null and __ancestor.key_schema <> '{}'::jsonb then
            select coalesce(jsonb_object_agg(k, _resource_id->k), '{}'::jsonb)
            from jsonb_object_keys(__ancestor.key_schema) as k
            where _resource_id ? k
            into __ancestor_key;
        else
            __ancestor_key := _resource_id;
        end if;

        __ancestor_key := coalesce(__ancestor_key, '{}'::jsonb);

        -- (a) User-level DENY
        if exists (
            select 1 from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = __ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = __ancestor_key)
              and ra.user_id = _user_id
              and ra.access_flag = _required_flag
              and ra.is_deny = true
        ) then
            if _throw_err then
                perform error.raise_35001(_user_id, _resource_type, _resource_id, _tenant_id);
            end if;
            return false;
        end if;

        -- (b) User-level GRANT
        if exists (
            select 1 from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = __ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = __ancestor_key)
              and ra.user_id = _user_id
              and ra.access_flag = _required_flag
              and ra.is_deny = false
        ) then
            return true;
        end if;

        -- (c) User role GRANT
        if exists (
            select 1 from auth.resource_role_assignment rra
            inner join const.resource_role_flag rrf
                on rrf.resource_role_code = rra.role_code
            where rra.root_type = __root_type
              and rra.resource_type = __ancestor.code
              and rra.tenant_id = _tenant_id
              and (rra.resource_path is null
                   or (__resource_path_lt is not null and __resource_path_lt <@ rra.resource_path))
              and (rra.resource_id = '{}'::jsonb or rra.resource_id = __ancestor_key)
              and rra.user_id = _user_id
              and rrf.access_flag_code = _required_flag
        ) then
            return true;
        end if;

        -- (d) Group-level GRANT
        if exists (
            select 1 from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = __ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = __ancestor_key)
              and ra.user_group_id = any(__cached_group_ids)
              and ra.access_flag = _required_flag
              and ra.is_deny = false
        ) then
            return true;
        end if;

        -- (e) Group role GRANT
        if exists (
            select 1 from auth.resource_role_assignment rra
            inner join const.resource_role_flag rrf
                on rrf.resource_role_code = rra.role_code
            where rra.root_type = __root_type
              and rra.resource_type = __ancestor.code
              and rra.tenant_id = _tenant_id
              and (rra.resource_path is null
                   or (__resource_path_lt is not null and __resource_path_lt <@ rra.resource_path))
              and (rra.resource_id = '{}'::jsonb or rra.resource_id = __ancestor_key)
              and rra.user_group_id = any(__cached_group_ids)
              and rrf.access_flag_code = _required_flag
        ) then
            return true;
        end if;
    end loop;

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
    _user_id         bigint,
    _correlation_id  text,
    _resource_type   text,
    _resource_ids    jsonb[] default null,
    _required_flag   text    default 'read',
    _tenant_id       integer default 1,
    _resource_paths  text[]  default null
) returns table(__resource_id jsonb)
    language plpgsql
as
$$
declare
    __cached_group_ids   integer[];
    __root_type          text;
    __ancestor_types     text[];
    __resource_paths_lt  ext.ltree[];
begin
    if _resource_ids is null and _resource_paths is null then
        return;
    end if;

    if _resource_paths is not null then
        select array_agg(ext.text2ltree(p))
        from unnest(_resource_paths) as p
        into __resource_paths_lt;
    end if;

    if _user_id = 1 or auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        if _resource_ids is not null then
            return query select unnest(_resource_ids);
        end if;
        if _resource_paths is not null then
            return query select jsonb_build_object('path', p) from unnest(_resource_paths) as p;
        end if;
        return;
    end if;

    __cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    __root_type        := split_part(_resource_type, '.', 1);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into __ancestor_types;

    -- ID-based filtering (composite-key rows only; path rows are excluded)
    if _resource_ids is not null then
        return query
        select r.id
        from unnest(_resource_ids) as r(id)
        where not exists (
            select 1 from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = any(__ancestor_types)
              and ra.tenant_id = _tenant_id
              and ra.resource_path is null
              and ra.resource_id @> r.id
              and ra.user_id = _user_id
              and ra.access_flag = _required_flag
              and ra.is_deny = true
        )
        and (
            exists (
                select 1 from auth.resource_access ra
                where ra.root_type = __root_type
                  and ra.resource_type = any(__ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is null
                  and ra.resource_id @> r.id
                  and ra.user_id = _user_id
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = __root_type
                  and rra.resource_type = any(__ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is null
                  and rra.resource_id @> r.id
                  and rra.user_id = _user_id
                  and rrf.access_flag_code = _required_flag
            )
            or exists (
                select 1 from auth.resource_access ra
                where ra.root_type = __root_type
                  and ra.resource_type = any(__ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is null
                  and ra.resource_id @> r.id
                  and ra.user_group_id = any(__cached_group_ids)
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = __root_type
                  and rra.resource_type = any(__ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is null
                  and rra.resource_id @> r.id
                  and rra.user_group_id = any(__cached_group_ids)
                  and rrf.access_flag_code = _required_flag
            )
        );
    end if;

    -- Path-based filtering (ancestor-walk via <@)
    if __resource_paths_lt is not null then
        return query
        select jsonb_build_object('path', p.path::text)
        from unnest(__resource_paths_lt) as p(path)
        where not exists (
            select 1 from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = any(__ancestor_types)
              and ra.tenant_id = _tenant_id
              and ra.resource_path is not null
              and p.path <@ ra.resource_path
              and ra.user_id = _user_id
              and ra.access_flag = _required_flag
              and ra.is_deny = true
        )
        and (
            exists (
                select 1 from auth.resource_access ra
                where ra.root_type = __root_type
                  and ra.resource_type = any(__ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is not null
                  and p.path <@ ra.resource_path
                  and ra.user_id = _user_id
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = __root_type
                  and rra.resource_type = any(__ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is not null
                  and p.path <@ rra.resource_path
                  and rra.user_id = _user_id
                  and rrf.access_flag_code = _required_flag
            )
            or exists (
                select 1 from auth.resource_access ra
                where ra.root_type = __root_type
                  and ra.resource_type = any(__ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is not null
                  and p.path <@ ra.resource_path
                  and ra.user_group_id = any(__cached_group_ids)
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = __root_type
                  and rra.resource_type = any(__ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is not null
                  and p.path <@ rra.resource_path
                  and rra.user_group_id = any(__cached_group_ids)
                  and rrf.access_flag_code = _required_flag
            )
        );
    end if;
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
    _resource_id    jsonb   default '{}'::jsonb,
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns table(__access_flag text, __source text)
    language plpgsql
as
$$
declare
    __cached_group_ids integer[];
    __root_type        text;
    __ancestor_types   text[];
    __resource_path_lt ext.ltree;
begin
    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    if _user_id = 1 then
        return query
            select raf.code, 'system'::text
            from const.resource_access_flag raf;
        return;
    end if;

    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return query
            select raf.code, 'owner'::text
            from const.resource_access_flag raf;
        return;
    end if;

    __cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    __root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __resource_path_lt := ext.text2ltree(_resource_path);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into __ancestor_types;

    return query
    with matching as (
        select ra.access_flag, ra.is_deny, ra.user_id, ra.user_group_id, null::text as role_code
        from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.resource_type = any(__ancestor_types)
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and (ra.user_id = _user_id or ra.user_group_id = any(__cached_group_ids))
        union all
        select rrf.access_flag_code, false, rra.user_id, rra.user_group_id, rra.role_code
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        where rra.root_type = __root_type
          and rra.resource_type = any(__ancestor_types)
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and (rra.user_id = _user_id or rra.user_group_id = any(__cached_group_ids))
    ),
    denied_flags as (
        select access_flag
        from matching
        where user_id = _user_id and is_deny = true
    ),
    direct_grants as (
        select distinct access_flag, 'direct'::text as source
        from matching
        where user_id = _user_id
          and is_deny = false
          and role_code is null
          and access_flag not in (select access_flag from denied_flags)
    ),
    user_role_grants as (
        select distinct m.access_flag,
               ('role:' || m.role_code)::text as source
        from matching m
        where m.user_id = _user_id
          and m.role_code is not null
          and m.access_flag not in (select access_flag from denied_flags)
          and m.access_flag not in (select access_flag from direct_grants)
    ),
    group_grants as (
        select distinct on (m.access_flag) m.access_flag, ug.title as source
        from matching m
        inner join auth.user_group ug on ug.user_group_id = m.user_group_id
        where m.user_group_id is not null
          and m.is_deny = false
          and m.role_code is null
          and m.access_flag not in (select access_flag from denied_flags)
          and m.access_flag not in (select access_flag from direct_grants)
          and m.access_flag not in (select access_flag from user_role_grants)
        order by m.access_flag, ug.title
    ),
    group_role_grants as (
        select distinct on (m.access_flag) m.access_flag,
               (ug.title || ' (role:' || m.role_code || ')')::text as source
        from matching m
        inner join auth.user_group ug on ug.user_group_id = m.user_group_id
        where m.user_group_id is not null
          and m.role_code is not null
          and m.access_flag not in (select access_flag from denied_flags)
          and m.access_flag not in (select access_flag from direct_grants)
          and m.access_flag not in (select access_flag from user_role_grants)
          and m.access_flag not in (select access_flag from group_grants)
        order by m.access_flag, ug.title
    )
    select * from direct_grants
    union all select * from user_role_grants
    union all select * from group_grants
    union all select * from group_role_grants;
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
    _resource_id    jsonb   default '{}'::jsonb,
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns table(
    __resource_type text,
    __access_flag   text,
    __source        text
)
    language plpgsql
as
$$
declare
    __cached_group_ids integer[];
    __root_type        text;
    __is_owner         boolean;
    __resource_path_lt ext.ltree;
begin
    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    -- System user gets all valid flags on all descendant types
    if _user_id = 1 then
        return query
            select rt.code, raf.code, 'system'::text
            from const.resource_type rt
            cross join const.resource_access_flag raf
            where rt.path <@ (select path from const.resource_type where code = _resource_type)
              and rt.is_active = true
              and (not exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
                   or exists (select 1 from const.resource_type_flag rtf where rtf.resource_type_code = rt.code and rtf.access_flag_code = raf.code));
        return;
    end if;

    -- Tenant owner gets all valid flags on all descendant types
    __is_owner := auth.is_owner(_user_id, _correlation_id, null, _tenant_id);
    if __is_owner then
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

    __cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    __root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __resource_path_lt := ext.text2ltree(_resource_path);

    return query
    with descendant_types as (
        select rt.code, rt.path
        from const.resource_type rt
        where rt.path <@ (select path from const.resource_type where code = _resource_type)
          and rt.is_active = true
    ),
    denied_flags as (
        select ra.resource_type, ra.access_flag
        from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and ra.user_id = _user_id
          and ra.is_deny = true
          and ra.resource_type in (select dt.code from descendant_types dt)
    ),
    direct_grants as (
        select ra.resource_type, ra.access_flag, 'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and ra.user_id = _user_id
          and ra.is_deny = false
          and ra.resource_type in (select dt.code from descendant_types dt)
    ),
    user_role_grants as (
        select rra.resource_type, rrf.access_flag_code as access_flag,
               ('role:' || rra.role_code)::text as source
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        where rra.root_type = __root_type
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and rra.user_id = _user_id
          and rra.resource_type in (select dt.code from descendant_types dt)
    ),
    group_grants as (
        select distinct on (ra.resource_type, ra.access_flag)
            ra.resource_type, ra.access_flag, ug.title as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = __root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and ra.user_group_id = any(__cached_group_ids)
          and ra.is_deny = false
          and ra.resource_type in (select dt.code from descendant_types dt)
        order by ra.resource_type, ra.access_flag, ug.title
    ),
    group_role_grants as (
        select distinct on (rra.resource_type, rrf.access_flag_code)
               rra.resource_type, rrf.access_flag_code as access_flag,
               (ug.title || ' (role:' || rra.role_code || ')')::text as source
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        inner join auth.user_group ug on ug.user_group_id = rra.user_group_id
        where rra.root_type = __root_type
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (__resource_path_lt is not null and __resource_path_lt <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and rra.user_group_id = any(__cached_group_ids)
          and rra.resource_type in (select dt.code from descendant_types dt)
        order by rra.resource_type, rrf.access_flag_code, ug.title
    ),
    all_grants as (
        -- Priority: direct > user_role > group > group_role
        select dg.resource_type, dg.access_flag, dg.source from direct_grants dg
        union all
        select urg.resource_type, urg.access_flag, urg.source from user_role_grants urg
        where not exists (
            select 1 from direct_grants dg2
            where dg2.resource_type = urg.resource_type and dg2.access_flag = urg.access_flag
        )
        union all
        select gg.resource_type, gg.access_flag, gg.source from group_grants gg
        where not exists (
            select 1 from direct_grants dg3
            where dg3.resource_type = gg.resource_type and dg3.access_flag = gg.access_flag
        )
        and not exists (
            select 1 from user_role_grants urg2
            where urg2.resource_type = gg.resource_type and urg2.access_flag = gg.access_flag
        )
        union all
        select grg.resource_type, grg.access_flag, grg.source from group_role_grants grg
        where not exists (
            select 1 from direct_grants dg4
            where dg4.resource_type = grg.resource_type and dg4.access_flag = grg.access_flag
        )
        and not exists (
            select 1 from user_role_grants urg3
            where urg3.resource_type = grg.resource_type and urg3.access_flag = grg.access_flag
        )
        and not exists (
            select 1 from group_grants gg2
            where gg2.resource_type = grg.resource_type and gg2.access_flag = grg.access_flag
        )
    ),
    explicit_grants as (
        -- Filter out denied flags
        select ag.resource_type, ag.access_flag, ag.source
        from all_grants ag
        where not exists (
            select 1 from denied_flags df
            where df.resource_type = ag.resource_type
              and df.access_flag = ag.access_flag
        )
    ),
    -- Inheritance: parent grant cascades to children (unless denied or explicit)
    inherited_grants as (
        select dt.code as resource_type, eg.access_flag, eg.source
        from explicit_grants eg
        inner join const.resource_type parent_rt on parent_rt.code = eg.resource_type
        inner join descendant_types dt on dt.path <@ parent_rt.path and dt.code <> eg.resource_type
        where not exists (
            select 1 from denied_flags df
            where df.resource_type = dt.code
              and df.access_flag = eg.access_flag
        )
        and not exists (
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
-- Grant: auth.assign_resource_access
-- ============================================================================
--
-- Grant one or more flags to a user or group.
-- UPSERT: if exists as deny, flips is_deny to false.
-- resource_id is jsonb — validated against key_schema.
--
create or replace function auth.assign_resource_access(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb   default '{}'::jsonb,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns table(__resource_access_id bigint, __access_flag text)
    language plpgsql
as
$$
declare
    __flag           text;
    __last_id       bigint;
    __target_type    text;
    __target_name    text;
    __root_type      text;
    __resource_path_lt ext.ltree;
begin
    -- Permission check
    perform auth.has_permission(_user_id, _correlation_id, 'resources.grant_access', _tenant_id);

    -- Validate target
    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    __resource_path_lt := ext.text2ltree(_resource_path);

    -- Validate resource type, flags (global + per-type), and resource_id key schema
    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_access_flags(_access_flags);
    perform unsecure.validate_access_flags_for_type(_resource_type, _access_flags);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    _resource_id := coalesce(_resource_id, '{}'::jsonb);
    __root_type   := split_part(_resource_type, '.', 1);

    if _target_user_id is not null then
        __target_type := 'user';
        select coalesce(display_name, code, user_id::text)
        from auth.user_info where user_id = _target_user_id
        into __target_name;
    else
        __target_type := 'group';
        select coalesce(title, code, user_group_id::text)
        from auth.user_group where user_group_id = _user_group_id
        into __target_name;
    end if;

    foreach __flag in array _access_flags
    loop
        __last_id := null;

        if _target_user_id is not null then
            select ra.resource_access_id from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = _resource_type
              and ra.tenant_id = _tenant_id
              and ra.resource_id = _resource_id
              and ra.resource_path is not distinct from __resource_path_lt
              and ra.user_id = _target_user_id
              and ra.access_flag = __flag
            into __last_id;
        else
            select ra.resource_access_id from auth.resource_access ra
            where ra.root_type = __root_type
              and ra.resource_type = _resource_type
              and ra.tenant_id = _tenant_id
              and ra.resource_id = _resource_id
              and ra.resource_path is not distinct from __resource_path_lt
              and ra.user_group_id = _user_group_id
              and ra.access_flag = __flag
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
              and root_type = __root_type;
        else
            -- Insert new grant
            insert into auth.resource_access (
                created_by, updated_by, tenant_id, resource_type, root_type,
                resource_id, resource_path,
                user_id, user_group_id, access_flag, is_deny, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, __root_type,
                _resource_id, __resource_path_lt,
                _target_user_id, _user_group_id, __flag, false, _user_id
            )
            returning resource_access_id into __last_id;
        end if;

        return query select __last_id, __flag;
    end loop;

    -- Journal
    perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18010  -- resource_access_granted
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'target_type', __target_type, 'target_name', __target_name,
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
    _resource_id    jsonb   default '{}'::jsonb,
    _target_user_id bigint  default null,
    _access_flags   text[]  default array['read'],
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns table(__resource_access_id bigint, __access_flag text)
    language plpgsql
as
$$
declare
    __flag             text;
    __last_id         bigint;
    __target_name      text;
    __root_type        text;
    __resource_path_lt ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.deny_access', _tenant_id);

    if _target_user_id is null then
        raise exception 'Deny requires _target_user_id (denies on groups are not supported)'
            using errcode = '35002';
    end if;

    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_access_flags(_access_flags);
    perform unsecure.validate_access_flags_for_type(_resource_type, _access_flags);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __root_type        := split_part(_resource_type, '.', 1);
    __resource_path_lt := ext.text2ltree(_resource_path);

    select coalesce(display_name, code, user_id::text)
    from auth.user_info where user_id = _target_user_id
    into __target_name;

    foreach __flag in array _access_flags
    loop
        select ra.resource_access_id from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.resource_type = _resource_type
          and ra.tenant_id = _tenant_id
          and ra.resource_id = _resource_id
          and ra.resource_path is not distinct from __resource_path_lt
          and ra.user_id = _target_user_id
          and ra.access_flag = __flag
        into __last_id;

        if __last_id is not null then
            update auth.resource_access
            set is_deny = true,
                updated_by = _created_by,
                updated_at = now(),
                granted_by = _user_id
            where resource_access_id = __last_id
              and root_type = __root_type;
        else
            insert into auth.resource_access (
                created_by, updated_by, tenant_id, resource_type, root_type,
                resource_id, resource_path,
                user_id, access_flag, is_deny, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, __root_type,
                _resource_id, __resource_path_lt,
                _target_user_id, __flag, true, _user_id
            )
            returning resource_access_id into __last_id;
        end if;

        return query select __last_id, __flag;
    end loop;

    perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18012  -- resource_access_denied
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'target_type', 'user', 'target_name', __target_name,
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
    _resource_id    jsonb   default '{}'::jsonb,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _access_flags   text[]  default null,
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count   bigint;
    __target_type      text;
    __target_name      text;
    __root_type        text;
    __resource_path_lt ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);

    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    perform unsecure.validate_resource_type(_resource_type);

    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __root_type        := split_part(_resource_type, '.', 1);
    __resource_path_lt := ext.text2ltree(_resource_path);

    if _target_user_id is not null then
        __target_type := 'user';
        select coalesce(display_name, code, user_id::text)
        from auth.user_info where user_id = _target_user_id
        into __target_name;
    else
        __target_type := 'group';
        select coalesce(title, code, user_group_id::text)
        from auth.user_group where user_group_id = _user_group_id
        into __target_name;
    end if;

    delete from auth.resource_access
    where root_type = __root_type
      and resource_type = _resource_type
      and tenant_id = _tenant_id
      and resource_id = _resource_id
      and resource_path is not distinct from __resource_path_lt
      and (_target_user_id is null or user_id = _target_user_id)
      and (_user_group_id is null or user_group_id = _user_group_id)
      and (_access_flags is null or access_flag = any(_access_flags));

    get diagnostics __deleted_count = row_count;

    perform public.create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18011  -- resource_access_revoked
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'target_type', __target_type, 'target_name', __target_name,
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
    _resource_id    jsonb   default '{}'::jsonb,
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count   bigint;
    __root_type        text;
    __resource_path_lt ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);
    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __root_type        := split_part(_resource_type, '.', 1);
    __resource_path_lt := ext.text2ltree(_resource_path);

    -- Composite-key cascade via jsonb @> (e.g. {"project_id": 42} matches
    -- {"project_id": 42, "folder_id": 100}); path cascade via ltree <@
    -- (drops self + descendants).
    delete from auth.resource_access
    where root_type = __root_type
      and tenant_id = _tenant_id
      and (_resource_id = '{}'::jsonb or resource_id @> _resource_id)
      and (__resource_path_lt is null or resource_path <@ __resource_path_lt);

    get diagnostics __deleted_count = row_count;

    perform public.create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18013  -- resource_access_bulk_revoked
        , 'resource_access', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
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
    _resource_id    jsonb   default '{}'::jsonb,
    _tenant_id      integer default 1,
    _resource_path  text    default null
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
    stable
    language plpgsql
as
$$
declare
    __root_type        text;
    __resource_path_lt ext.ltree;
begin
    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    _resource_id      := coalesce(_resource_id, '{}'::jsonb);
    __root_type        := split_part(_resource_type, '.', 1);
    __resource_path_lt := ext.text2ltree(_resource_path);

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
    where ra.root_type = __root_type
      and ra.resource_type = _resource_type
      and ra.tenant_id = _tenant_id
      and ra.resource_id = _resource_id
      and ra.resource_path is not distinct from __resource_path_lt

    union all

    select
        rra.resource_role_assignment_id,
        rra.user_id,
        ui2.display_name,
        rra.user_group_id,
        ug2.title,
        rrf.access_flag_code as access_flag,
        false as is_deny,
        rra.granted_by,
        gb2.display_name,
        rra.created_at
    from auth.resource_role_assignment rra
    inner join const.resource_role_flag rrf on rrf.resource_role_code = rra.role_code
    left join auth.user_info ui2 on ui2.user_id = rra.user_id
    left join auth.user_group ug2 on ug2.user_group_id = rra.user_group_id
    left join auth.user_info gb2 on gb2.user_id = rra.granted_by
    where rra.root_type = __root_type
      and rra.resource_type = _resource_type
      and rra.tenant_id = _tenant_id
      and rra.resource_id = _resource_id
      and rra.resource_path is not distinct from __resource_path_lt

    order by access_flag, is_deny, created_at;
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
    _access_flag     text    default 'read',
    _tenant_id       integer default 1
) returns table(
    __resource_id   jsonb,
    __resource_path text,
    __access_flags  text[],
    __source        text
)
    language plpgsql
as
$$
declare
    __cached_group_ids integer[];
    __root_type        text;
    __ancestor_types   text[];
begin
    if _user_id <> _target_user_id then
        perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);
    end if;

    __cached_group_ids := unsecure.get_cached_group_ids(_target_user_id, _tenant_id);
    __root_type        := split_part(_resource_type, '.', 1);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into __ancestor_types;

    return query
    with denied_flags as (
        select ra.resource_id, ra.resource_path, ra.access_flag
        from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.resource_type = any(__ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_id = _target_user_id
          and ra.is_deny = true
    ),
    direct_resources as (
        select ra.resource_id, ra.resource_path,
               array_agg(distinct ra.access_flag) as access_flags,
               'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = __root_type
          and ra.resource_type = any(__ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_id = _target_user_id
          and ra.is_deny = false
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = ra.resource_id
                and df.resource_path is not distinct from ra.resource_path
                and df.access_flag = ra.access_flag
          )
          and (_access_flag is null or ra.access_flag = _access_flag)
        group by ra.resource_id, ra.resource_path
    ),
    user_role_resources as (
        select rra.resource_id, rra.resource_path,
               array_agg(distinct rrf.access_flag_code) as access_flags,
               ('role:' || string_agg(distinct rra.role_code, ','))::text as source
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        where rra.root_type = __root_type
          and rra.resource_type = any(__ancestor_types)
          and rra.tenant_id = _tenant_id
          and rra.user_id = _target_user_id
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = rra.resource_id
                and df.resource_path is not distinct from rra.resource_path
                and df.access_flag = rrf.access_flag_code
          )
          and (_access_flag is null or rrf.access_flag_code = _access_flag)
          and not exists (
              select 1 from direct_resources dr
              where dr.resource_id = rra.resource_id
                and dr.resource_path is not distinct from rra.resource_path
          )
        group by rra.resource_id, rra.resource_path
    ),
    group_resources as (
        select ra.resource_id, ra.resource_path,
               array_agg(distinct ra.access_flag) as access_flags,
               string_agg(distinct ug.title, ', ') as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = __root_type
          and ra.resource_type = any(__ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_group_id = any(__cached_group_ids)
          and ra.is_deny = false
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = ra.resource_id
                and df.resource_path is not distinct from ra.resource_path
                and df.access_flag = ra.access_flag
          )
          and (_access_flag is null or ra.access_flag = _access_flag)
          and not exists (
              select 1 from direct_resources dr
              where dr.resource_id = ra.resource_id
                and dr.resource_path is not distinct from ra.resource_path
          )
          and not exists (
              select 1 from user_role_resources urr
              where urr.resource_id = ra.resource_id
                and urr.resource_path is not distinct from ra.resource_path
          )
        group by ra.resource_id, ra.resource_path
    ),
    group_role_resources as (
        select rra.resource_id, rra.resource_path,
               array_agg(distinct rrf.access_flag_code) as access_flags,
               (string_agg(distinct ug.title, ', ') || ' (role)')::text as source
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        inner join auth.user_group ug on ug.user_group_id = rra.user_group_id
        where rra.root_type = __root_type
          and rra.resource_type = any(__ancestor_types)
          and rra.tenant_id = _tenant_id
          and rra.user_group_id = any(__cached_group_ids)
          and not exists (
              select 1 from denied_flags df
              where df.resource_id = rra.resource_id
                and df.resource_path is not distinct from rra.resource_path
                and df.access_flag = rrf.access_flag_code
          )
          and (_access_flag is null or rrf.access_flag_code = _access_flag)
          and not exists (
              select 1 from direct_resources dr
              where dr.resource_id = rra.resource_id
                and dr.resource_path is not distinct from rra.resource_path
          )
          and not exists (
              select 1 from user_role_resources urr
              where urr.resource_id = rra.resource_id
                and urr.resource_path is not distinct from rra.resource_path
          )
          and not exists (
              select 1 from group_resources gr
              where gr.resource_id = rra.resource_id
                and gr.resource_path is not distinct from rra.resource_path
          )
        group by rra.resource_id, rra.resource_path
    )
    select dr.resource_id, dr.resource_path::text, dr.access_flags, dr.source from direct_resources dr
    union all
    select urr.resource_id, urr.resource_path::text, urr.access_flags, urr.source from user_role_resources urr
    union all
    select gr.resource_id, gr.resource_path::text, gr.access_flags, gr.source from group_resources gr
    union all
    select grr.resource_id, grr.resource_path::text, grr.access_flags, grr.source from group_role_resources grr;
end;
$$;

-- ============================================================================
-- Resource type CRUD, access flag CRUD, and translations-aware functions
-- ============================================================================

-- ============================================================================
-- auth.ensure_resource_type_flags
-- ============================================================================
-- Ensure a resource type has exactly the specified set of valid access flags.
-- Adds missing flags and removes flags not in the list.
-- Pass an empty array to remove all per-type mappings (allows all flags).
-- Pass null to leave existing mappings unchanged (no-op).
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
    __flag text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if _access_flags is null then
        return query
        select rtf.resource_type_code, rtf.access_flag_code
        from const.resource_type_flag rtf
        where rtf.resource_type_code = _resource_type
        order by rtf.access_flag_code;
        return;
    end if;

    if not exists (select 1 from const.resource_type where code = _resource_type) then
        perform error.raise_35003(_resource_type);
    end if;

    if array_length(_access_flags, 1) > 0 then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    delete from const.resource_type_flag
    where resource_type_code = _resource_type
      and access_flag_code != all(_access_flags);

    foreach __flag in array _access_flags
    loop
        insert into const.resource_type_flag (resource_type_code, access_flag_code)
        values (_resource_type, __flag)
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
-- 2. Helper: recompute full_title translations for a type and descendants
-- ============================================================================
-- Mirrors the old unsecure.update_resource_type_full_title but writes to
-- public.translation with context='full_title' instead of a column.
-- Called after any title translation is created/updated.
--
create or replace function unsecure.update_resource_type_full_title_translations(
    _path           ext.ltree,
    _language_code  text default 'en',
    _created_by     text default 'system'
) returns void
    language plpgsql
as
$$
declare
    __rt record;
    __full_title text;
begin
    for __rt in
        select code, path
        from const.resource_type
        where path <@ _path
        order by path
    loop
        -- Build breadcrumb from ancestor title translations
        select array_to_string(
            array(
                select coalesce(t.value, a.code)
                from const.resource_type a
                left join public.translation t
                    on t.data_group = 'resource_type' and t.data_object_code = a.code
                    and t.context = 'title' and t.language_code = _language_code
                where a.path @> __rt.path
                order by a.path
            ), ' > ')
        into __full_title;

        -- Upsert full_title translation
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', __rt.code, 'full_title', __full_title)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end loop;

    -- Refresh MV so reads see updated full_titles
    perform internal.refresh_translation_cache();
end;
$$;

-- ============================================================================
-- 3. Functions — resource type management
-- ============================================================================

-- auth.create_resource_type
create or replace function auth.create_resource_type(
    _created_by   text,
    _user_id      bigint,
    _correlation_id text,
    _code         text,
    _title        text,
    _description  text default null,
    _tenant_id    integer default 1,
    _source       text default null,
    _key_schema   jsonb default '{}'::jsonb,
    _access_flags text[] default null,
    _language_code text default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __path         text,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    ___path ext.ltree;
    __flag text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    ___path := ext.text2ltree(_code);

    insert into const.resource_type (code, source, path, key_schema)
    values (_code, _source, ___path, coalesce(_key_schema, '{}'::jsonb))
    on conflict do nothing;

    -- Translations for title + description
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', _code, 'title', _title)
        on conflict do nothing;
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', _code, 'description', _description)
        on conflict do nothing;
    end if;

    -- Recompute full_title for this type and all descendants
    perform unsecure.update_resource_type_full_title_translations(___path, _language_code, _created_by);

    if _access_flags is not null then
        foreach __flag in array _access_flags
        loop
            insert into const.resource_type_flag (resource_type_code, access_flag_code)
            values (_code, __flag) on conflict do nothing;
        end loop;
    end if;

    perform unsecure.ensure_resource_access_partition(_code);

    return query
        select rt.code,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code), rt.code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.path::text, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt where rt.code = _code;

    perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18001, 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title,
            'key_schema', _key_schema, 'access_flags', _access_flags)
        , _tenant_id);
end;
$$;

-- auth.update_resource_type
create or replace function auth.update_resource_type(
    _updated_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _title          text    default null,
    _description    text    default null,
    _is_active      boolean default null,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __path         text,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    ___path ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if not exists (select 1 from const.resource_type where code = _code) then
        perform error.raise_35003(_code);
    end if;

    select path from const.resource_type where code = _code into ___path;

    update const.resource_type
    set is_active = coalesce(_is_active, is_active),
        source    = coalesce(_source, source)
    where code = _code;

    -- Upsert translations
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_type', _code, 'title', _title)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();

        -- Recompute full_title for this type and all descendants
        perform unsecure.update_resource_type_full_title_translations(___path, _language_code, _updated_by);
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_type', _code, 'description', _description)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;

    return query
        select rt.code,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code), rt.code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.path::text, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt where rt.code = _code;

    perform public.create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18002, 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title, 'is_active', _is_active)
        , _tenant_id);
end;
$$;

-- auth.ensure_resource_types
create or replace function auth.ensure_resource_types(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_types jsonb,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __path         text,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    __item          jsonb;
    ___code          text;
    ___title         text;
    ___description   text;
    __item_source   text;
    ___key_schema    jsonb;
    ___access_flags  text[];
    __flag          text;
    ___path          ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for __item in
        select value from jsonb_array_elements(_resource_types)
        order by ext.nlevel(ext.text2ltree(value->>'code'))
    loop
        ___code        := __item->>'code';
        ___title       := __item->>'title';
        ___description := __item->>'description';
        __item_source := coalesce(__item->>'source', _source);
        ___key_schema  := coalesce(__item->'key_schema', '{}'::jsonb);
        ___path        := ext.text2ltree(___code);

        if __item ? 'access_flags' and __item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(__item->'access_flags') as f(value)
            into ___access_flags;
        else
            ___access_flags := null;
        end if;

        if not exists (select 1 from const.resource_type where code = ___code) then
            if ___access_flags is not null then
                perform unsecure.validate_access_flags(___access_flags);
            end if;

            insert into const.resource_type (code, source, path, key_schema)
            values (___code, __item_source, ___path, ___key_schema)
            on conflict do nothing;
        end if;

        -- Translations (upsert)
        if ___title is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_type', ___code, 'title', ___title)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;
        if ___description is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_type', ___code, 'description', ___description)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;

        -- Recompute full_title for this type and all descendants
        perform unsecure.update_resource_type_full_title_translations(___path, _language_code, _created_by);

        if ___access_flags is not null then
            foreach __flag in array ___access_flags
            loop
                insert into const.resource_type_flag (resource_type_code, access_flag_code)
                values (___code, __flag) on conflict do nothing;
            end loop;
        end if;

        perform unsecure.ensure_resource_access_partition(___code);

        perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18001, 'resource_type', 0
            , jsonb_build_object('resource_type', ___code, 'title', ___title,
                'key_schema', ___key_schema, 'access_flags', ___access_flags)
            , _tenant_id);
    end loop;

    return query
        select rt.code,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code), rt.code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.path::text, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt
        where rt.code in (select value->>'code' from jsonb_array_elements(_resource_types))
        order by rt.path;
end;
$$;

-- auth.get_resource_types
create or replace function auth.get_resource_types(
    _source        text    default null,
    _active_only   boolean default true,
    _language_code text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __path         text,
    __key_schema   jsonb,
    __access_flags text[]
)
    stable
    language plpgsql
as
$$
begin
    return query
    select rt.code,
           coalesce(mv.values->>'title', rt.code),
           mv.values->>'full_title',
           mv.values->>'description',
           rt.is_active, rt.source, rt.path::text, rt.key_schema,
           (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
            from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
    from const.resource_type rt
    left join public.mv_translation mv
        on mv.data_group = 'resource_type' and mv.data_object_code = rt.code
        and mv.language_code = _language_code
    where (_active_only = false or rt.is_active = true)
      and (_source is null or rt.source = _source)
    order by rt.path;
end;
$$;

-- ============================================================================
-- 5. Replaced functions — access flag management
-- ============================================================================

-- auth.ensure_access_flags
create or replace function auth.ensure_access_flags(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _flags          jsonb,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(__code text, __title text, __source text)
    language plpgsql
as
$$
declare
    __item jsonb;
    ___code text;
    ___title text;
    __item_source text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for __item in select value from jsonb_array_elements(_flags)
    loop
        ___code        := __item->>'code';
        ___title       := __item->>'title';
        __item_source := coalesce(__item->>'source', _source);

        if ___code is null or ___title is null then
            raise exception 'Access flag requires both "code" and "title" fields'
                using errcode = '35004';
        end if;

        insert into const.resource_access_flag (code, source)
        values (___code, __item_source)
        on conflict do nothing;

        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_access_flag', ___code, 'title', ___title)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end loop;

    perform internal.refresh_translation_cache();

    return query
    select f.code,
           coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_access_flag' and mv.data_object_code = f.code and mv.language_code = _language_code), f.code),
           f.source
    from const.resource_access_flag f
    where f.code in (select value->>'code' from jsonb_array_elements(_flags))
    order by f.code;
end;
$$;

-- auth.get_access_flags
create or replace function auth.get_access_flags(
    _source        text default null,
    _language_code text default 'en'
) returns table(__code text, __title text, __source text)
    stable
    language plpgsql
as
$$
begin
    return query
    select f.code,
           coalesce(mv.values->>'title', f.code),
           f.source
    from const.resource_access_flag f
    left join public.mv_translation mv
        on mv.data_group = 'resource_access_flag' and mv.data_object_code = f.code
        and mv.language_code = _language_code
    where (_source is null or f.source = _source)
    order by f.code;
end;
$$;

-- ============================================================================
