/*
 * Translation Context Column
 * ===========================
 *
 * Adds `context` to public.translation so a single (group, code/id) can carry
 * multiple translated values — e.g. title + description for a resource_type,
 * or label + tooltip for a UI element.
 *
 * Before:  (language, group, code)           → value   (one per object)
 * After:   (language, group, code, context)   → value   (many per object)
 *
 * Backward compatible: context defaults to null. Existing rows stay null.
 * The unique indexes use coalesce(context, '') so null still means "the one".
 *
 * Updated functions: create, update, delete, copy, get_group, search.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- context column and indexes are now in 030_tables_language.sql (CREATE TABLE)
-- This section kept empty for existing DB compatibility (045 still runs, no-ops)

-- ============================================================================
-- 3. Update translation functions
-- ============================================================================

-- ---------------------------------------------------------------------------
-- create_translation — added _context parameter
-- ---------------------------------------------------------------------------
-- Drop the old signature to avoid ambiguous overloads
drop function if exists public.create_translation(text, bigint, text, text, text, text, text, bigint, integer);

create or replace function public.create_translation(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _language_code text,
    _data_group text,
    _value text,
    _data_object_code text default null,
    _data_object_id bigint default null,
    _context text default null,
    _tenant_id integer default 1
)
    returns setof public.translation
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.create_translation', _tenant_id);

    if not exists (select 1 from const.language where code = _language_code) then
        perform error.raise_37001(_language_code);
    end if;

    return query
        insert into public.translation (created_by, updated_by, language_code, tenant_id,
            data_group, data_object_code, data_object_id, context, value)
        values (_created_by, _created_by, _language_code, _tenant_id,
            _data_group, _data_object_code, _data_object_id, _context, _value)
        returning *;

    -- Refresh materialized view
    perform unsecure.refresh_translation_cache();

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 21001  -- translation_created
        , null::jsonb
        , jsonb_strip_nulls(jsonb_build_object(
            'language_code', _language_code, 'data_group', _data_group,
            'data_object_code', _data_object_code, 'data_object_id', _data_object_id,
            'context', _context))
        , _tenant_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- update_translation — unchanged signature (updates by translation_id)
-- ---------------------------------------------------------------------------
-- No changes needed — update targets by PK, context is already in the row.

-- ---------------------------------------------------------------------------
-- delete_translation — unchanged signature (deletes by translation_id)
-- ---------------------------------------------------------------------------
-- No changes needed — delete targets by PK.

-- ---------------------------------------------------------------------------
-- copy_translations — context-aware matching
-- ---------------------------------------------------------------------------
drop function if exists public.copy_translations(text, bigint, text, text, text, boolean, text, integer, integer, integer);

create or replace function public.copy_translations(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _from_language_code text,
    _to_language_code text,
    _overwrite boolean default false,
    _data_group text default null,
    _from_tenant_id integer default 1,
    _to_tenant_id integer default 1,
    _tenant_id integer default 1
)
    returns table(__operation text, __count bigint)
    language plpgsql
as
$$
declare
    __updated_count bigint := 0;
    __inserted_count bigint := 0;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.copy_translations', _tenant_id);

    if not exists (select 1 from const.language where code = _from_language_code) then
        perform error.raise_37001(_from_language_code);
    end if;
    if not exists (select 1 from const.language where code = _to_language_code) then
        perform error.raise_37001(_to_language_code);
    end if;

    -- Phase 1: Update existing translations if overwrite is enabled
    if _overwrite then
        with source as (
            select data_group, data_object_code, data_object_id, context, value
            from public.translation
            where language_code = _from_language_code
                and tenant_id = _from_tenant_id
                and (_data_group is null or data_group = _data_group)
        )
        update public.translation t
        set value      = s.value
          , updated_by = _created_by
          , updated_at = now()
        from source s
        where t.language_code = _to_language_code
            and t.tenant_id = _to_tenant_id
            and t.data_group = s.data_group
            and coalesce(t.context, '') = coalesce(s.context, '')
            and (
                (t.data_object_code is not null and t.data_object_code = s.data_object_code)
                or (t.data_object_id is not null and t.data_object_id = s.data_object_id)
            );

        get diagnostics __updated_count = row_count;
    end if;

    -- Phase 2: Insert missing translations
    insert into public.translation (created_by, updated_by, language_code, tenant_id,
        data_group, data_object_code, data_object_id, context, value)
    select _created_by, _created_by, _to_language_code, _to_tenant_id,
        s.data_group, s.data_object_code, s.data_object_id, s.context, s.value
    from public.translation s
    where s.language_code = _from_language_code
        and s.tenant_id = _from_tenant_id
        and (_data_group is null or s.data_group = _data_group)
        and not exists (
            select 1 from public.translation e
            where e.language_code = _to_language_code
                and e.tenant_id = _to_tenant_id
                and e.data_group = s.data_group
                and coalesce(e.context, '') = coalesce(s.context, '')
                and (
                    (s.data_object_code is not null and e.data_object_code = s.data_object_code)
                    or (s.data_object_id is not null and e.data_object_id = s.data_object_id)
                )
        );

    get diagnostics __inserted_count = row_count;

    -- Refresh materialized view
    perform unsecure.refresh_translation_cache();

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 21004  -- translations_copied
        , null::jsonb
        , jsonb_build_object(
            'from_language', _from_language_code, 'to_language', _to_language_code,
            'overwrite', _overwrite, 'data_group', _data_group,
            'updated_count', __updated_count, 'inserted_count', __inserted_count)
        , _tenant_id);

    return query
        select 'updated'::text, __updated_count
        union all
        select 'inserted'::text, __inserted_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_group_translations — returns context-aware structure
-- ---------------------------------------------------------------------------
-- Old behavior (context = null):  {"code1": "value1", "code2": "value2"}
-- New behavior (mixed contexts):  {"code1": {"title": "...", "description": "..."}, "code2": "value"}
--
-- If all rows for a group have context = null (legacy), output is flat (backward compat).
-- If any row has a non-null context, ALL codes in that group get nested objects.
--
-- Added _context parameter for filtering to a single context (returns flat map).
--
drop function if exists public.get_group_translations(text, text, integer);

create or replace function public.get_group_translations(
    _language_code text,
    _data_group text,
    _context text default null,
    _tenant_id integer default 1
)
    returns jsonb
    stable
    language plpgsql
as
$$
begin
    -- Specific context → flat map: {"code1": "value1", "code2": "value2"}
    if _context is not null then
        return (
            select coalesce(
                jsonb_object_agg(mv.data_object_code, mv.values->>_context),
                '{}'::jsonb
            )
            from public.mv_translation mv
            where mv.language_code = _language_code
                and mv.data_group = _data_group
                and mv.data_object_code is not null
                and mv.tenant_id = _tenant_id
                and mv.values ? _context
        );
    end if;

    -- All contexts → nested: {"code": {"title": "...", "description": "..."}}
    return (
        select coalesce(
            jsonb_object_agg(mv.data_object_code, mv.values),
            '{}'::jsonb
        )
        from public.mv_translation mv
        where mv.language_code = _language_code
            and mv.data_group = _data_group
            and mv.data_object_code is not null
            and mv.tenant_id = _tenant_id
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- search_translations — added _context filter
-- ---------------------------------------------------------------------------
drop function if exists public.search_translations(bigint, text, text, text, text, text, text, bigint, integer, integer, integer);

create or replace function public.search_translations(
    _user_id bigint,
    _correlation_id text,
    _display_language_code text default 'en',
    _search_text text default null,
    _language_code text default null,
    _data_group text default null,
    _data_object_code text default null,
    _data_object_id bigint default null,
    _context text default null,
    _page integer default 1,
    _page_size integer default 10,
    _tenant_id integer default 1
)
    returns table(
        __translation_id integer,
        __language_code text,
        __language_value text,
        __data_group text,
        __data_object_code text,
        __data_object_id bigint,
        __context text,
        __value text,
        __created_at timestamptz,
        __created_by text,
        __updated_at timestamptz,
        __updated_by text,
        __total_items bigint
    )
    stable
    rows 100
    language plpgsql
as
$$
declare
    __search_text text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.read_translations', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := case when _page is null then 1 else _page end;
    _page_size := case when _page_size is null then 10 else least(_page_size, 100) end;

    return query
        with filtered_rows as (
            select t.translation_id
                 , count(*) over () as total_items
            from public.translation t
            where t.tenant_id = _tenant_id
                and (_language_code is null or t.language_code = _language_code)
                and (_data_group is null or t.data_group = _data_group)
                and (_data_object_code is null or t.data_object_code = _data_object_code)
                and (_data_object_id is null or t.data_object_id = _data_object_id)
                and (_context is null or t.context = _context)
                and (helpers.is_empty_string(__search_text)
                    or t.nrm_search_data like '%' || __search_text || '%')
            order by t.data_group, t.data_object_code, t.context, t.language_code
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select t.translation_id
             , t.language_code
             , l.value as language_value
             , t.data_group
             , t.data_object_code
             , t.data_object_id
             , t.context
             , t.value
             , t.created_at
             , t.created_by
             , t.updated_at
             , t.updated_by
             , fr.total_items
        from filtered_rows fr
        inner join public.translation t on fr.translation_id = t.translation_id
        inner join const.language l on t.language_code = l.code;
end;
$$;
