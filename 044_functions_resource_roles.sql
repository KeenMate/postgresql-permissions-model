/*
 * Resource Roles — Functions
 * ===========================
 *
 * Role management:
 *   1.  auth.create_resource_role          — register a new role with flags
 *   2.  auth.ensure_resource_roles         — bulk-ensure roles from JSONB
 *   3.  auth.update_resource_role          — update title/description/active/source
 *   4.  auth.delete_resource_role          — remove a role (cascade assignments)
 *   5.  auth.ensure_resource_role_flags    — set exact flag set for a role
 *   6.  auth.get_resource_roles            — list roles (public metadata)
 *   7.  auth.get_resource_role_flags       — list flags in a role
 *
 * Role assignment:
 *   8.  auth.assign_resource_role          — assign role(s) to user/group on resource
 *   9.  auth.revoke_resource_role          — revoke role(s) from user/group on resource
 *  10.  auth.revoke_all_resource_roles     — revoke all roles on a resource
 *  11.  auth.get_resource_role_assignments — list role assignments on a resource
 *
 * Updated check functions (union role-derived flags):
 *  12.  auth.has_resource_access           — now checks role assignments too
 *  13.  auth.filter_accessible_resources   — now includes role-derived access
 *  14.  auth.get_resource_access_flags     — includes role-sourced flags
 *  15.  auth.get_resource_access_matrix    — includes role-sourced flags
 *
 * Updated query functions (include role assignments in results):
 *  16.  auth.get_resource_grants           — now includes role assignments
 *  17.  auth.get_user_accessible_resources — now includes role-derived resources
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Validation helper
-- ============================================================================

/*
 * unsecure.validate_resource_role — Checks that a role code exists and is active.
 */
create or replace function unsecure.validate_resource_role(_role_code text)
returns void
    language plpgsql
as
$$
begin
    if not exists (
        select 1 from const.resource_role
        where code = _role_code and is_active = true
    ) then
        perform error.raise_35007(_role_code);
    end if;
end;
$$;

/*
 * unsecure.validate_role_flags_for_type — Validates that every flag in a role
 * is valid for the role's resource_type (via const.resource_type_flag).
 * Skips validation when the resource_type has no per-type flag restrictions.
 */
create or replace function unsecure.validate_role_flags_for_type(
    _role_code      text,
    _resource_type  text,
    _access_flags   text[]
) returns void
    language plpgsql
as
$$
declare
    _flag text;
    _has_type_flags boolean;
begin
    select exists(
        select 1 from const.resource_type_flag where resource_type_code = _resource_type
    ) into _has_type_flags;

    if not _has_type_flags then
        return;
    end if;

    foreach _flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_type_flag
            where resource_type_code = _resource_type and access_flag_code = _flag
        ) then
            perform error.raise_35008(_role_code, _resource_type, _flag);
        end if;
    end loop;
end;
$$;

-- ============================================================================
-- 1-3. auth.create_resource_role, ensure_resource_roles, update_resource_role
-- are defined below (translations-aware versions).
-- ============================================================================

-- ============================================================================
-- 4. auth.delete_resource_role
-- ============================================================================
-- Deletes a role and cascades to all assignments (via FK on delete cascade).
--
create or replace function auth.delete_resource_role(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _tenant_id      integer default 1
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count bigint;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if not exists (select 1 from const.resource_role where code = _code) then
        perform error.raise_35007(_code);
    end if;

    delete from const.resource_role where code = _code;
    get diagnostics __deleted_count = row_count;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18005  -- resource_role_deleted
        , 'resource_role', 0
        , jsonb_build_object('role_code', _code)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- ============================================================================
-- 5. auth.ensure_resource_role_flags
-- ============================================================================
-- Set exact flag set for a role. Mirrors auth.ensure_resource_type_flags.
--   null  → no-op (return current flags)
--   empty → remove all flags
--   array → set to exactly these flags (add missing, remove extras)
--
create or replace function auth.ensure_resource_role_flags(
    _updated_by     text,
    _user_id        bigint,
    _correlation_id text,
    _role_code      text,
    _access_flags   text[],
    _tenant_id      integer default 1
) returns table(__resource_role_code text, __access_flag_code text)
    language plpgsql
as
$$
declare
    _flag          text;
    _resource_type text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    -- Null = no-op
    if _access_flags is null then
        return query
        select rrf.resource_role_code, rrf.access_flag_code
        from const.resource_role_flag rrf
        where rrf.resource_role_code = _role_code
        order by rrf.access_flag_code;
        return;
    end if;

    -- Validate role exists
    if not exists (select 1 from const.resource_role where code = _role_code) then
        perform error.raise_35007(_role_code);
    end if;

    -- Resolve resource_type for per-type flag validation
    select resource_type from const.resource_role where code = _role_code into _resource_type;

    -- Validate all flags exist globally
    if array_length(_access_flags, 1) > 0 then
        perform unsecure.validate_access_flags(_access_flags);
        perform unsecure.validate_role_flags_for_type(_role_code, _resource_type, _access_flags);
    end if;

    -- Remove flags not in the new list
    delete from const.resource_role_flag
    where resource_role_code = _role_code
      and access_flag_code != all(_access_flags);

    -- Add missing flags
    foreach _flag in array _access_flags
    loop
        insert into const.resource_role_flag (resource_role_code, access_flag_code)
        values (_role_code, _flag)
        on conflict do nothing;
    end loop;

    -- Journal
    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18004  -- resource_role_updated
        , 'resource_role', 0
        , jsonb_build_object('role_code', _role_code, 'access_flags', _access_flags)
        , _tenant_id);

    return query
    select rrf.resource_role_code, rrf.access_flag_code
    from const.resource_role_flag rrf
    where rrf.resource_role_code = _role_code
    order by rrf.access_flag_code;
end;
$$;

-- 6. auth.get_resource_roles — defined below

-- ============================================================================
-- 7. auth.get_resource_role_flags
-- ============================================================================
-- Public metadata — no RBAC check.
--
create or replace function auth.get_resource_role_flags(
    _role_code text
) returns table(__access_flag_code text)
    stable
    language plpgsql
as
$$
begin
    return query
    select rrf.access_flag_code
    from const.resource_role_flag rrf
    where rrf.resource_role_code = _role_code
    order by rrf.access_flag_code;
end;
$$;

-- ============================================================================
-- 8. auth.assign_resource_role
-- ============================================================================
-- Assign one or more roles to a user or group on a specific resource.
-- Idempotent (on conflict do nothing via unique index).
--
-- resource_id is validated against the role's resource_type key_schema.
--
create or replace function auth.assign_resource_role(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _target_user_id bigint    default null,
    _user_group_id  integer   default null,
    _role_codes     text[]    default null,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
) returns table(__resource_role_assignment_id bigint, __role_code text)
    language plpgsql
as
$$
declare
    _rc             text;
    __last_id       bigint;
    _target_type    text;
    _target_name    text;
    _root_type      text;
    _role_res_type  text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.grant_access', _tenant_id);

    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    if (_resource_id is null or _resource_id = '{}'::jsonb) and _resource_path is null then
        raise exception 'Either _resource_id (non-empty) or _resource_path must be provided'
            using errcode = '35005';
    end if;

    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    if _role_codes is null or array_length(_role_codes, 1) is null then
        raise exception 'At least one role_code must be provided'
            using errcode = '35007';
    end if;

    _resource_id := coalesce(_resource_id, '{}'::jsonb);
    _root_type   := split_part(_resource_type, '.', 1);

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

    foreach _rc in array _role_codes
    loop
        perform unsecure.validate_resource_role(_rc);

        select resource_type from const.resource_role where code = _rc into _role_res_type;
        if _role_res_type <> _resource_type then
            perform error.raise_35009(_rc, _role_res_type, _resource_type);
        end if;

        __last_id := null;
        if _target_user_id is not null then
            select rra.resource_role_assignment_id
            from auth.resource_role_assignment rra
            where rra.root_type = _root_type
              and rra.resource_type = _resource_type
              and rra.tenant_id = _tenant_id
              and rra.resource_id = _resource_id
              and rra.resource_path is not distinct from _resource_path
              and rra.user_id = _target_user_id
              and rra.role_code = _rc
            into __last_id;
        else
            select rra.resource_role_assignment_id
            from auth.resource_role_assignment rra
            where rra.root_type = _root_type
              and rra.resource_type = _resource_type
              and rra.tenant_id = _tenant_id
              and rra.resource_id = _resource_id
              and rra.resource_path is not distinct from _resource_path
              and rra.user_group_id = _user_group_id
              and rra.role_code = _rc
            into __last_id;
        end if;

        if __last_id is not null then
            update auth.resource_role_assignment
            set updated_by = _created_by,
                updated_at = now(),
                granted_by = _user_id
            where resource_role_assignment_id = __last_id
              and root_type = _root_type;
        else
            insert into auth.resource_role_assignment (
                created_by, updated_by, tenant_id, resource_type, root_type,
                resource_id, resource_path,
                user_id, user_group_id, role_code, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, _root_type,
                _resource_id, _resource_path,
                _target_user_id, _user_group_id, _rc, _user_id
            )
            returning resource_role_assignment_id into __last_id;
        end if;

        return query select __last_id, _rc;
    end loop;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18020  -- resource_role_assigned
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path::text, ''),
            'target_type', _target_type, 'target_name', _target_name,
            'role_codes', _role_codes)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- 9. auth.revoke_resource_role
-- ============================================================================
-- Revoke specific roles from a user/group on a resource.
-- If _role_codes is null, revokes ALL role assignments.
--
create or replace function auth.revoke_resource_role(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _target_user_id bigint    default null,
    _user_group_id  integer   default null,
    _role_codes     text[]    default null,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count bigint;
    _target_type    text;
    _target_name    text;
    _root_type      text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);

    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    perform unsecure.validate_resource_type(_resource_type);

    _resource_id := coalesce(_resource_id, '{}'::jsonb);
    _root_type   := split_part(_resource_type, '.', 1);

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

    delete from auth.resource_role_assignment
    where root_type = _root_type
      and resource_type = _resource_type
      and tenant_id = _tenant_id
      and resource_id = _resource_id
      and resource_path is not distinct from _resource_path
      and (_target_user_id is null or user_id = _target_user_id)
      and (_user_group_id is null or user_group_id = _user_group_id)
      and (_role_codes is null or role_code = any(_role_codes));

    get diagnostics __deleted_count = row_count;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18021  -- resource_role_revoked
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path::text, ''),
            'target_type', _target_type, 'target_name', _target_name,
            'role_codes', coalesce(_role_codes, array['*']),
            'deleted_count', __deleted_count)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- ============================================================================
-- 10. auth.revoke_all_resource_roles
-- ============================================================================
-- Revoke ALL role assignments on a resource (cleanup when resource is deleted).
-- Uses containment (@>) like revoke_all_resource_access.
--
create or replace function auth.revoke_all_resource_roles(
    _deleted_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
) returns bigint
    language plpgsql
as
$$
declare
    __deleted_count bigint;
    _root_type      text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.revoke_access', _tenant_id);
    perform unsecure.validate_resource_type(_resource_type);

    if (_resource_id is null or _resource_id = '{}'::jsonb) and _resource_path is null then
        raise exception 'Either _resource_id (non-empty) or _resource_path must be provided'
            using errcode = '35005';
    end if;

    _resource_id := coalesce(_resource_id, '{}'::jsonb);
    _root_type   := split_part(_resource_type, '.', 1);

    delete from auth.resource_role_assignment
    where root_type = _root_type
      and tenant_id = _tenant_id
      and (_resource_id = '{}'::jsonb or resource_id @> _resource_id)
      and (_resource_path is null or resource_path <@ _resource_path);

    get diagnostics __deleted_count = row_count;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18021  -- resource_role_revoked
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path::text, ''),
            'deleted_count', __deleted_count)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- 11. auth.get_resource_role_assignments — defined below

-- ============================================================================
-- Drop older signatures from 035 so the new ones below replace cleanly
-- (without creating overloaded pairs with different arities).
-- ============================================================================
drop function if exists auth.has_resource_access(bigint, text, text, jsonb, text, integer, boolean);
drop function if exists auth.filter_accessible_resources(bigint, text, text, jsonb[], text, integer);
drop function if exists auth.get_resource_access_flags(bigint, text, text, jsonb, integer);
drop function if exists auth.get_resource_access_matrix(bigint, text, text, jsonb, integer);
drop function if exists auth.get_resource_grants(bigint, text, text, jsonb, integer);
drop function if exists auth.get_user_accessible_resources(bigint, text, bigint, text, text, integer);

-- ============================================================================
-- 12. auth.has_resource_access (REPLACED)
-- ============================================================================
-- Added: steps 4 and 6 check resource_role_assignment + resource_role_flag.
-- Deny-overrides algorithm with hierarchy walk-up:
-- 1. System user → true
-- 2. Tenant owner → true
-- 3. Get cached group IDs
-- 4. Walk up the type hierarchy (most specific first):
--    a. User-level DENY     (resource_access)       → false
--    b. User-level GRANT    (resource_access)       → true
--    c. User role GRANT     (resource_role_assignment) → true
--    d. Group-level GRANT   (resource_access)       → true
--    e. Group role GRANT    (resource_role_assignment) → true
-- 5. No grant found → false (or throw error)
--
create or replace function auth.has_resource_access(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _required_flag  text      default 'read',
    _tenant_id      integer   default 1,
    _throw_err      boolean   default true,
    _resource_path  ext.ltree default null
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
    if _user_id = 1 then
        return true;
    end if;

    if auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        return true;
    end if;

    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    _root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);

    for _ancestor in
        select rt.code, rt.key_schema
        from const.resource_type rt
        where rt.path @> (select path from const.resource_type where code = _resource_type)
          and rt.is_active = true
        order by ext.nlevel(rt.path) desc
    loop
        -- Build the id-component lookup key for this ancestor
        if _ancestor.key_schema is not null and _ancestor.key_schema <> '{}'::jsonb then
            select coalesce(jsonb_object_agg(k, _resource_id->k), '{}'::jsonb)
            from jsonb_object_keys(_ancestor.key_schema) as k
            where _resource_id ? k
            into _ancestor_key;
        else
            _ancestor_key := _resource_id;
        end if;

        _ancestor_key := coalesce(_ancestor_key, '{}'::jsonb);

        -- (a) User-level DENY
        if exists (
            select 1 from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = _ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (_resource_path is not null and _resource_path <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = _ancestor_key)
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
            where ra.root_type = _root_type
              and ra.resource_type = _ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (_resource_path is not null and _resource_path <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = _ancestor_key)
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
            where rra.root_type = _root_type
              and rra.resource_type = _ancestor.code
              and rra.tenant_id = _tenant_id
              and (rra.resource_path is null
                   or (_resource_path is not null and _resource_path <@ rra.resource_path))
              and (rra.resource_id = '{}'::jsonb or rra.resource_id = _ancestor_key)
              and rra.user_id = _user_id
              and rrf.access_flag_code = _required_flag
        ) then
            return true;
        end if;

        -- (d) Group-level GRANT
        if exists (
            select 1 from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = _ancestor.code
              and ra.tenant_id = _tenant_id
              and (ra.resource_path is null
                   or (_resource_path is not null and _resource_path <@ ra.resource_path))
              and (ra.resource_id = '{}'::jsonb or ra.resource_id = _ancestor_key)
              and ra.user_group_id = any(_cached_group_ids)
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
            where rra.root_type = _root_type
              and rra.resource_type = _ancestor.code
              and rra.tenant_id = _tenant_id
              and (rra.resource_path is null
                   or (_resource_path is not null and _resource_path <@ rra.resource_path))
              and (rra.resource_id = '{}'::jsonb or rra.resource_id = _ancestor_key)
              and rra.user_group_id = any(_cached_group_ids)
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
-- 13. auth.filter_accessible_resources (REPLACED)
-- ============================================================================
-- Added: role-derived grants unioned with direct flag grants.
--
create or replace function auth.filter_accessible_resources(
    _user_id         bigint,
    _correlation_id  text,
    _resource_type   text,
    _resource_ids    jsonb[]     default null,
    _required_flag   text        default 'read',
    _tenant_id       integer     default 1,
    _resource_paths  ext.ltree[] default null
) returns table(__resource_id jsonb)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
    if _resource_ids is null and _resource_paths is null then
        return;
    end if;

    if _user_id = 1 or auth.is_owner(_user_id, _correlation_id, null, _tenant_id) then
        if _resource_ids is not null then
            return query select unnest(_resource_ids);
        end if;
        if _resource_paths is not null then
            return query select jsonb_build_object('path', p::text) from unnest(_resource_paths) as p;
        end if;
        return;
    end if;

    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    _root_type        := split_part(_resource_type, '.', 1);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    -- ID-based filtering (composite-key rows only; path rows are excluded)
    if _resource_ids is not null then
        return query
        select r.id
        from unnest(_resource_ids) as r(id)
        where not exists (
            select 1 from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = any(_ancestor_types)
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
                where ra.root_type = _root_type
                  and ra.resource_type = any(_ancestor_types)
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
                where rra.root_type = _root_type
                  and rra.resource_type = any(_ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is null
                  and rra.resource_id @> r.id
                  and rra.user_id = _user_id
                  and rrf.access_flag_code = _required_flag
            )
            or exists (
                select 1 from auth.resource_access ra
                where ra.root_type = _root_type
                  and ra.resource_type = any(_ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is null
                  and ra.resource_id @> r.id
                  and ra.user_group_id = any(_cached_group_ids)
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = _root_type
                  and rra.resource_type = any(_ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is null
                  and rra.resource_id @> r.id
                  and rra.user_group_id = any(_cached_group_ids)
                  and rrf.access_flag_code = _required_flag
            )
        );
    end if;

    -- Path-based filtering (ancestor-walk via <@)
    if _resource_paths is not null then
        return query
        select jsonb_build_object('path', p.path::text)
        from unnest(_resource_paths) as p(path)
        where not exists (
            select 1 from auth.resource_access ra
            where ra.root_type = _root_type
              and ra.resource_type = any(_ancestor_types)
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
                where ra.root_type = _root_type
                  and ra.resource_type = any(_ancestor_types)
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
                where rra.root_type = _root_type
                  and rra.resource_type = any(_ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is not null
                  and p.path <@ rra.resource_path
                  and rra.user_id = _user_id
                  and rrf.access_flag_code = _required_flag
            )
            or exists (
                select 1 from auth.resource_access ra
                where ra.root_type = _root_type
                  and ra.resource_type = any(_ancestor_types)
                  and ra.tenant_id = _tenant_id
                  and ra.resource_path is not null
                  and p.path <@ ra.resource_path
                  and ra.user_group_id = any(_cached_group_ids)
                  and ra.access_flag = _required_flag
                  and ra.is_deny = false
            )
            or exists (
                select 1 from auth.resource_role_assignment rra
                inner join const.resource_role_flag rrf
                    on rrf.resource_role_code = rra.role_code
                where rra.root_type = _root_type
                  and rra.resource_type = any(_ancestor_types)
                  and rra.tenant_id = _tenant_id
                  and rra.resource_path is not null
                  and p.path <@ rra.resource_path
                  and rra.user_group_id = any(_cached_group_ids)
                  and rrf.access_flag_code = _required_flag
            )
        );
    end if;
end;
$$;

-- ============================================================================
-- 14. auth.get_resource_access_flags (REPLACED)
-- ============================================================================
-- Added: role-sourced flags with source = 'role:<role_code>' or group title.
--
create or replace function auth.get_resource_access_flags(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
) returns table(__access_flag text, __source text)
    language plpgsql
as
$$
declare
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
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

    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    _root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    return query
    with matching as (
        select ra.access_flag, ra.is_deny, ra.user_id, ra.user_group_id, null::text as role_code
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (_resource_path is not null and _resource_path <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and (ra.user_id = _user_id or ra.user_group_id = any(_cached_group_ids))
        union all
        select rrf.access_flag_code, false, rra.user_id, rra.user_group_id, rra.role_code
        from auth.resource_role_assignment rra
        inner join const.resource_role_flag rrf
            on rrf.resource_role_code = rra.role_code
        where rra.root_type = _root_type
          and rra.resource_type = any(_ancestor_types)
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (_resource_path is not null and _resource_path <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and (rra.user_id = _user_id or rra.user_group_id = any(_cached_group_ids))
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
-- 15. auth.get_resource_access_matrix (REPLACED)
-- ============================================================================
-- Added: role-sourced flags at each hierarchy level.
--
create or replace function auth.get_resource_access_matrix(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
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

    _cached_group_ids := unsecure.get_cached_group_ids(_user_id, _tenant_id);
    _root_type        := split_part(_resource_type, '.', 1);
    _resource_id      := coalesce(_resource_id, '{}'::jsonb);

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
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (_resource_path is not null and _resource_path <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and ra.user_id = _user_id
          and ra.is_deny = true
          and ra.resource_type in (select dt.code from descendant_types dt)
    ),
    direct_grants as (
        select ra.resource_type, ra.access_flag, 'direct'::text as source
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (_resource_path is not null and _resource_path <@ ra.resource_path))
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
        where rra.root_type = _root_type
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (_resource_path is not null and _resource_path <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and rra.user_id = _user_id
          and rra.resource_type in (select dt.code from descendant_types dt)
    ),
    group_grants as (
        select distinct on (ra.resource_type, ra.access_flag)
            ra.resource_type, ra.access_flag, ug.title as source
        from auth.resource_access ra
        inner join auth.user_group ug on ug.user_group_id = ra.user_group_id
        where ra.root_type = _root_type
          and ra.tenant_id = _tenant_id
          and (ra.resource_path is null
               or (_resource_path is not null and _resource_path <@ ra.resource_path))
          and (ra.resource_id = '{}'::jsonb or ra.resource_id @> _resource_id)
          and ra.user_group_id = any(_cached_group_ids)
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
        where rra.root_type = _root_type
          and rra.tenant_id = _tenant_id
          and (rra.resource_path is null
               or (_resource_path is not null and _resource_path <@ rra.resource_path))
          and (rra.resource_id = '{}'::jsonb or rra.resource_id @> _resource_id)
          and rra.user_group_id = any(_cached_group_ids)
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
-- 16. auth.get_resource_grants (REPLACED)
-- ============================================================================
-- Added: includes role assignments alongside direct flag grants.
--
create or replace function auth.get_resource_grants(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb     default '{}'::jsonb,
    _tenant_id      integer   default 1,
    _resource_path  ext.ltree default null
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
    _root_type text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    _resource_id := coalesce(_resource_id, '{}'::jsonb);
    _root_type   := split_part(_resource_type, '.', 1);

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
      and ra.resource_path is not distinct from _resource_path

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
    where rra.root_type = _root_type
      and rra.resource_type = _resource_type
      and rra.tenant_id = _tenant_id
      and rra.resource_id = _resource_id
      and rra.resource_path is not distinct from _resource_path

    order by access_flag, is_deny, created_at;
end;
$$;

-- ============================================================================
-- 17. auth.get_user_accessible_resources (REPLACED)
-- ============================================================================
-- Added: resources accessible via role assignments.
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
    _cached_group_ids integer[];
    _root_type        text;
    _ancestor_types   text[];
begin
    if _user_id <> _target_user_id then
        perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);
    end if;

    _cached_group_ids := unsecure.get_cached_group_ids(_target_user_id, _tenant_id);
    _root_type        := split_part(_resource_type, '.', 1);

    select array_agg(rt.code)
    from const.resource_type rt
    where rt.path @> (select path from const.resource_type where code = _resource_type)
      and rt.is_active = true
    into _ancestor_types;

    return query
    with denied_flags as (
        select ra.resource_id, ra.resource_path, ra.access_flag
        from auth.resource_access ra
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_id = _target_user_id
          and ra.is_deny = true
    ),
    direct_resources as (
        select ra.resource_id, ra.resource_path,
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
        where rra.root_type = _root_type
          and rra.resource_type = any(_ancestor_types)
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
        where ra.root_type = _root_type
          and ra.resource_type = any(_ancestor_types)
          and ra.tenant_id = _tenant_id
          and ra.user_group_id = any(_cached_group_ids)
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
        where rra.root_type = _root_type
          and rra.resource_type = any(_ancestor_types)
          and rra.tenant_id = _tenant_id
          and rra.user_group_id = any(_cached_group_ids)
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
-- 6. Replaced functions — resource role management
-- ============================================================================

-- auth.create_resource_role
create or replace function auth.create_resource_role(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _resource_type  text,
    _title          text,
    _description    text    default null,
    _access_flags   text[]  default null,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
declare
    _flag text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);
    perform unsecure.validate_resource_type(_resource_type);

    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
        perform unsecure.validate_role_flags_for_type(_code, _resource_type, _access_flags);
    end if;

    insert into const.resource_role (code, resource_type, source)
    values (_code, _resource_type, _source)
    on conflict do nothing;

    -- Translations
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_role', _code, 'title', _title)
        on conflict do nothing;
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_role', _code, 'description', _description)
        on conflict do nothing;
    end if;

    if _access_flags is not null then
        foreach _flag in array _access_flags
        loop
            insert into const.resource_role_flag (resource_role_code, access_flag_code)
            values (_code, _flag) on conflict do nothing;
        end loop;
    end if;

    perform internal.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code), r.code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r where r.code = _code;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18003, 'resource_role', 0
        , jsonb_build_object('role_code', _code, 'resource_type', _resource_type,
            'title', _title, 'access_flags', _access_flags, 'source', _source)
        , _tenant_id);
end;
$$;

-- auth.ensure_resource_roles
create or replace function auth.ensure_resource_roles(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _roles          jsonb,
    _source         text    default null,
    _is_final_state boolean default false,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
declare
    _item          jsonb;
    _code          text;
    _res_type      text;
    _title         text;
    _desc          text;
    _item_source   text;
    _access_flags  text[];
    _flag          text;
    _existing_code text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for _item in select value from jsonb_array_elements(_roles)
    loop
        _code       := _item->>'code';
        _res_type   := _item->>'resource_type';
        _title      := _item->>'title';
        _desc       := _item->>'description';
        _item_source := coalesce(_item->>'source', _source);

        if _item ? 'access_flags' and _item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(_item->'access_flags') as f(value)
            into _access_flags;
        else
            _access_flags := null;
        end if;

        perform unsecure.validate_resource_type(_res_type);

        if _access_flags is not null then
            perform unsecure.validate_access_flags(_access_flags);
            perform unsecure.validate_role_flags_for_type(_code, _res_type, _access_flags);
        end if;

        if exists (select 1 from const.resource_role where code = _code) then
            update const.resource_role
            set source    = coalesce(_item_source, source),
                is_active = true
            where code = _code;
        else
            insert into const.resource_role (code, resource_type, source)
            values (_code, _res_type, _item_source);
        end if;

        -- Translations (upsert)
        if _title is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', _code, 'title', _title)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;
        if _desc is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', _code, 'description', _desc)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;

        if _access_flags is not null then
            delete from const.resource_role_flag
            where resource_role_code = _code and access_flag_code != all(_access_flags);
            foreach _flag in array _access_flags
            loop
                insert into const.resource_role_flag (resource_role_code, access_flag_code)
                values (_code, _flag) on conflict do nothing;
            end loop;
        end if;

        perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18003, 'resource_role', 0
            , jsonb_build_object('role_code', _code, 'resource_type', _res_type,
                'title', _title, 'access_flags', _access_flags)
            , _tenant_id);
    end loop;

    if _is_final_state and _source is not null then
        for _existing_code in
            select r.code from const.resource_role r
            where r.source = _source and r.is_active = true
              and r.code not in (select value->>'code' from jsonb_array_elements(_roles))
        loop
            update const.resource_role set is_active = false where code = _existing_code;
        end loop;
    end if;

    perform internal.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code), r.code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r
        where r.code in (select value->>'code' from jsonb_array_elements(_roles))
        order by r.resource_type, r.code;
end;
$$;

-- auth.update_resource_role
create or replace function auth.update_resource_role(
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
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if not exists (select 1 from const.resource_role where code = _code) then
        perform error.raise_35007(_code);
    end if;

    update const.resource_role
    set is_active = coalesce(_is_active, is_active),
        source    = coalesce(_source, source)
    where code = _code;

    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_role', _code, 'title', _title)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_role', _code, 'description', _description)
        on conflict (language_code, data_group, data_object_code, context)
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;

    perform internal.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               coalesce((select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code), r.code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r where r.code = _code;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18004, 'resource_role', 0
        , jsonb_build_object('role_code', _code, 'title', _title, 'is_active', _is_active)
        , _tenant_id);
end;
$$;

-- auth.get_resource_roles
create or replace function auth.get_resource_roles(
    _source        text    default null,
    _resource_type text    default null,
    _active_only   boolean default true,
    _language_code text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    stable
    language plpgsql
as
$$
begin
    return query
    select r.code, r.resource_type,
           coalesce(mv.values->>'title', r.code),
           mv.values->>'description',
           r.is_active, r.source,
           (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
            from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
    from const.resource_role r
    left join public.mv_translation mv
        on mv.data_group = 'resource_role' and mv.data_object_code = r.code
        and mv.language_code = _language_code
    where (_active_only = false or r.is_active = true)
      and (_source is null or r.source = _source)
      and (_resource_type is null or r.resource_type = _resource_type)
    order by r.resource_type, r.code;
end;
$$;

-- auth.get_resource_role_assignments
create or replace function auth.get_resource_role_assignments(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __resource_role_assignment_id bigint,
    __user_id            bigint,
    __user_display_name  text,
    __user_group_id      integer,
    __group_title        text,
    __role_code          text,
    __role_title         text,
    __access_flags       text[],
    __granted_by         bigint,
    __granted_by_name    text,
    __created_at         timestamptz
)
    stable
    language plpgsql
as
$$
declare
    _root_type text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    _root_type := split_part(_resource_type, '.', 1);

    return query
    select
        rra.resource_role_assignment_id,
        rra.user_id,
        ui.display_name,
        rra.user_group_id,
        ug.title,
        rra.role_code,
        coalesce(mv_role.values->>'title', rra.role_code),
        (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
         from const.resource_role_flag rrf where rrf.resource_role_code = rra.role_code),
        rra.granted_by,
        gb.display_name,
        rra.created_at
    from auth.resource_role_assignment rra
    left join auth.user_info ui on ui.user_id = rra.user_id
    left join auth.user_group ug on ug.user_group_id = rra.user_group_id
    left join public.mv_translation mv_role
        on mv_role.data_group = 'resource_role' and mv_role.data_object_code = rra.role_code
        and mv_role.language_code = _language_code
    left join auth.user_info gb on gb.user_id = rra.granted_by
    where rra.root_type = _root_type
      and rra.resource_type = _resource_type
      and rra.tenant_id = _tenant_id
      and rra.resource_id = _resource_id
    order by rra.role_code, rra.created_at;
end;
$$;
