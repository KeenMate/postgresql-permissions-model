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
 * The resource-access check and query functions (has_resource_access,
 * filter_accessible_resources, get_resource_access_flags,
 * get_resource_access_matrix, get_resource_grants, get_user_accessible_resources)
 * union role-derived flags. Their single canonical definitions live in
 * 035_functions_resource_access.sql, alongside the ACL functions and the role
 * tables (034_tables_resource_access.sql), so there is one definition per
 * function rather than an ACL version here overriding an earlier one.
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
    __flag text;
    __has_type_flags boolean;
begin
    select exists(
        select 1 from const.resource_type_flag where resource_type_code = _resource_type
    ) into __has_type_flags;

    if not __has_type_flags then
        return;
    end if;

    foreach __flag in array _access_flags
    loop
        if not exists (
            select 1 from const.resource_type_flag
            where resource_type_code = _resource_type and access_flag_code = __flag
        ) then
            perform error.raise_35008(_role_code, _resource_type, __flag);
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

    perform public.create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
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
    __flag          text;
    __resource_type text;
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
    select resource_type from const.resource_role where code = _role_code into __resource_type;

    -- Validate all flags exist globally
    if array_length(_access_flags, 1) > 0 then
        perform unsecure.validate_access_flags(_access_flags);
        perform unsecure.validate_role_flags_for_type(_role_code, __resource_type, _access_flags);
    end if;

    -- Remove flags not in the new list
    delete from const.resource_role_flag
    where resource_role_code = _role_code
      and access_flag_code != all(_access_flags);

    -- Add missing flags
    foreach __flag in array _access_flags
    loop
        insert into const.resource_role_flag (resource_role_code, access_flag_code)
        values (_role_code, __flag)
        on conflict do nothing;
    end loop;

    -- Journal
    perform public.create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
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
    _resource_id    jsonb   default '{}'::jsonb,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _role_codes     text[]  default null,
    _tenant_id      integer default 1,
    _resource_path  text    default null
) returns table(__resource_role_assignment_id bigint, __role_code text)
    language plpgsql
as
$$
declare
    __rc               text;
    __last_id         bigint;
    __target_type      text;
    __target_name      text;
    __root_type        text;
    __role_res_type    text;
    __resource_path_lt ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.grant_access', _tenant_id);

    if _target_user_id is null and _user_group_id is null then
        perform error.raise_35002();
    end if;

    perform unsecure.validate_resource_identifier(_resource_id, _resource_path);

    perform unsecure.validate_resource_type(_resource_type);
    perform unsecure.validate_resource_id(_resource_type, _resource_id);

    if _role_codes is null or array_length(_role_codes, 1) is null then
        raise exception 'At least one role_code must be provided'
            using errcode = '35007';
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

    foreach __rc in array _role_codes
    loop
        perform unsecure.validate_resource_role(__rc);

        select resource_type from const.resource_role where code = __rc into __role_res_type;
        if __role_res_type <> _resource_type then
            perform error.raise_35009(__rc, __role_res_type, _resource_type);
        end if;

        __last_id := null;
        if _target_user_id is not null then
            select rra.resource_role_assignment_id
            from auth.resource_role_assignment rra
            where rra.root_type = __root_type
              and rra.resource_type = _resource_type
              and rra.tenant_id = _tenant_id
              and rra.resource_id = _resource_id
              and rra.resource_path is not distinct from __resource_path_lt
              and rra.user_id = _target_user_id
              and rra.role_code = __rc
            into __last_id;
        else
            select rra.resource_role_assignment_id
            from auth.resource_role_assignment rra
            where rra.root_type = __root_type
              and rra.resource_type = _resource_type
              and rra.tenant_id = _tenant_id
              and rra.resource_id = _resource_id
              and rra.resource_path is not distinct from __resource_path_lt
              and rra.user_group_id = _user_group_id
              and rra.role_code = __rc
            into __last_id;
        end if;

        if __last_id is not null then
            update auth.resource_role_assignment
            set updated_by = _created_by,
                updated_at = now(),
                granted_by = _user_id
            where resource_role_assignment_id = __last_id
              and root_type = __root_type;
        else
            insert into auth.resource_role_assignment (
                created_by, updated_by, tenant_id, resource_type, root_type,
                resource_id, resource_path,
                user_id, user_group_id, role_code, granted_by
            ) values (
                _created_by, _created_by, _tenant_id, _resource_type, __root_type,
                _resource_id, __resource_path_lt,
                _target_user_id, _user_group_id, __rc, _user_id
            )
            returning resource_role_assignment_id into __last_id;
        end if;

        return query select __last_id, __rc;
    end loop;

    perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18020  -- resource_role_assigned
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'target_type', __target_type, 'target_name', __target_name,
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
    _resource_id    jsonb   default '{}'::jsonb,
    _target_user_id bigint  default null,
    _user_group_id  integer default null,
    _role_codes     text[]  default null,
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

    delete from auth.resource_role_assignment
    where root_type = __root_type
      and resource_type = _resource_type
      and tenant_id = _tenant_id
      and resource_id = _resource_id
      and resource_path is not distinct from __resource_path_lt
      and (_target_user_id is null or user_id = _target_user_id)
      and (_user_group_id is null or user_group_id = _user_group_id)
      and (_role_codes is null or role_code = any(_role_codes));

    get diagnostics __deleted_count = row_count;

    perform public.create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18021  -- resource_role_revoked
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'target_type', __target_type, 'target_name', __target_name,
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

    delete from auth.resource_role_assignment
    where root_type = __root_type
      and tenant_id = _tenant_id
      and (_resource_id = '{}'::jsonb or resource_id @> _resource_id)
      and (__resource_path_lt is null or resource_path <@ __resource_path_lt);

    get diagnostics __deleted_count = row_count;

    perform public.create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 18021  -- resource_role_revoked
        , 'resource_role_assignment', 0
        , jsonb_build_object('resource_type', _resource_type, 'resource_id', _resource_id,
            'resource_path', coalesce(_resource_path, ''),
            'deleted_count', __deleted_count)
        , _tenant_id);

    return __deleted_count;
end;
$$;

-- 11. auth.get_resource_role_assignments — defined below

-- ============================================================================
-- Resource role management (create / ensure / update / get / assignments)
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
    __flag text;
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
        foreach __flag in array _access_flags
        loop
            insert into const.resource_role_flag (resource_role_code, access_flag_code)
            values (_code, __flag) on conflict do nothing;
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

    perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
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
    __item          jsonb;
    ___code          text;
    __res_type      text;
    ___title         text;
    __desc          text;
    __item_source   text;
    ___access_flags  text[];
    __flag          text;
    __existing_code text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for __item in select value from jsonb_array_elements(_roles)
    loop
        ___code       := __item->>'code';
        __res_type   := __item->>'resource_type';
        ___title      := __item->>'title';
        __desc       := __item->>'description';
        __item_source := coalesce(__item->>'source', _source);

        if __item ? 'access_flags' and __item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(__item->'access_flags') as f(value)
            into ___access_flags;
        else
            ___access_flags := null;
        end if;

        perform unsecure.validate_resource_type(__res_type);

        if ___access_flags is not null then
            perform unsecure.validate_access_flags(___access_flags);
            perform unsecure.validate_role_flags_for_type(___code, __res_type, ___access_flags);
        end if;

        if exists (select 1 from const.resource_role where code = ___code) then
            update const.resource_role
            set source    = coalesce(__item_source, source),
                is_active = true
            where code = ___code;
        else
            insert into const.resource_role (code, resource_type, source)
            values (___code, __res_type, __item_source);
        end if;

        -- Translations (upsert)
        if ___title is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', ___code, 'title', ___title)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;
        if __desc is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', ___code, 'description', __desc)
            on conflict (language_code, data_group, data_object_code, context)
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;

        if ___access_flags is not null then
            delete from const.resource_role_flag
            where resource_role_code = ___code and access_flag_code != all(___access_flags);
            foreach __flag in array ___access_flags
            loop
                insert into const.resource_role_flag (resource_role_code, access_flag_code)
                values (___code, __flag) on conflict do nothing;
            end loop;
        end if;

        perform public.create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18003, 'resource_role', 0
            , jsonb_build_object('role_code', ___code, 'resource_type', __res_type,
                'title', ___title, 'access_flags', ___access_flags)
            , _tenant_id);
    end loop;

    if _is_final_state and _source is not null then
        for __existing_code in
            select r.code from const.resource_role r
            where r.source = _source and r.is_active = true
              and r.code not in (select value->>'code' from jsonb_array_elements(_roles))
        loop
            update const.resource_role set is_active = false where code = __existing_code;
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

    perform public.create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
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
    __root_type text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    __root_type := split_part(_resource_type, '.', 1);

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
    where rra.root_type = __root_type
      and rra.resource_type = _resource_type
      and rra.tenant_id = _tenant_id
      and rra.resource_id = _resource_id
    order by rra.role_code, rra.created_at;
end;
$$;
