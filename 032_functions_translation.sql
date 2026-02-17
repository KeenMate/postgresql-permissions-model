/*
 * Translation Functions
 * =====================
 *
 * CRUD, copy, and search functions for public.translation
 *
 * Functions:
 * - public.create_translation     - Create a new translation (18001)
 * - public.update_translation     - Update an existing translation (18002)
 * - public.delete_translation     - Delete a translation (18003)
 * - public.copy_translations      - Copy translations between languages (18004)
 * - public.get_group_translations - Get all translations for a group as jsonb
 * - public.search_translations    - Paginated search with accent-insensitive matching
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- create_translation
-- ============================================================================
create or replace function public.create_translation(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _language_code text,
    _data_group text,
    _value text,
    _data_object_code text DEFAULT null,
    _data_object_id bigint DEFAULT null,
    _tenant_id integer DEFAULT 1
)
    returns setof public.translation
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.create_translation', _tenant_id);

    if not exists (select 1 from const.language where code = _language_code) then
        perform error.raise_35001(_language_code);
    end if;

    return query
        insert into public.translation (created_by, updated_by, language_code, tenant_id,
            data_group, data_object_code, data_object_id, value)
        values (_created_by, _created_by, _language_code, _tenant_id,
            _data_group, _data_object_code, _data_object_id, _value)
        returning *;

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 18001  -- translation_created
        , null::jsonb  -- keys
        , jsonb_strip_nulls(jsonb_build_object(
            'language_code', _language_code, 'data_group', _data_group,
            'data_object_code', _data_object_code, 'data_object_id', _data_object_id))
        , _tenant_id);
end;
$$;

-- ============================================================================
-- update_translation
-- ============================================================================
create or replace function public.update_translation(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _translation_id integer,
    _value text,
    _tenant_id integer DEFAULT 1
)
    returns setof public.translation
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.update_translation', _tenant_id);

    if not exists (select 1 from public.translation where translation_id = _translation_id) then
        perform error.raise_35002(_translation_id);
    end if;

    return query
        update public.translation
        set updated_by = _created_by
          , updated_at = now()
          , value      = _value
        where translation_id = _translation_id
        returning *;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18002  -- translation_updated
        , 'translation', _translation_id::bigint
        , jsonb_build_object('translation_id', _translation_id, 'value', _value)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- delete_translation
-- ============================================================================
create or replace function public.delete_translation(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _translation_id integer,
    _tenant_id integer DEFAULT 1
)
    returns void
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.delete_translation', _tenant_id);

    if not exists (select 1 from public.translation where translation_id = _translation_id) then
        perform error.raise_35002(_translation_id);
    end if;

    delete from public.translation where translation_id = _translation_id;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18003  -- translation_deleted
        , 'translation', _translation_id::bigint
        , jsonb_build_object('translation_id', _translation_id)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- copy_translations
-- ============================================================================
create or replace function public.copy_translations(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _from_language_code text,
    _to_language_code text,
    _overwrite boolean DEFAULT false,
    _data_group text DEFAULT null,
    _from_tenant_id integer DEFAULT 1,
    _to_tenant_id integer DEFAULT 1,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(__operation text, __count bigint)
    language plpgsql
as
$$
declare
    __updated_count bigint := 0;
    __inserted_count bigint := 0;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'translations.copy_translations', _tenant_id);

    if not exists (select 1 from const.language where code = _from_language_code) then
        perform error.raise_35001(_from_language_code);
    end if;
    if not exists (select 1 from const.language where code = _to_language_code) then
        perform error.raise_35001(_to_language_code);
    end if;

    -- Phase 1: Update existing translations if overwrite is enabled
    if _overwrite then
        with source as (
            select data_group, data_object_code, data_object_id, value
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
            and (
                (t.data_object_code is not null and t.data_object_code = s.data_object_code)
                or (t.data_object_id is not null and t.data_object_id = s.data_object_id)
            );

        get diagnostics __updated_count = row_count;
    end if;

    -- Phase 2: Insert missing translations
    insert into public.translation (created_by, updated_by, language_code, tenant_id,
        data_group, data_object_code, data_object_id, value)
    select _created_by, _created_by, _to_language_code, _to_tenant_id,
        s.data_group, s.data_object_code, s.data_object_id, s.value
    from public.translation s
    where s.language_code = _from_language_code
        and s.tenant_id = _from_tenant_id
        and (_data_group is null or s.data_group = _data_group)
        and not exists (
            select 1 from public.translation e
            where e.language_code = _to_language_code
                and e.tenant_id = _to_tenant_id
                and e.data_group = s.data_group
                and (
                    (s.data_object_code is not null and e.data_object_code = s.data_object_code)
                    or (s.data_object_id is not null and e.data_object_id = s.data_object_id)
                )
        );

    get diagnostics __inserted_count = row_count;

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 18004  -- translations_copied
        , null::jsonb  -- keys
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

-- ============================================================================
-- get_group_translations
-- ============================================================================
create or replace function public.get_group_translations(
    _language_code text,
    _data_group text,
    _tenant_id integer DEFAULT 1
)
    returns jsonb
    stable
    language sql
as
$$
select coalesce(
    jsonb_object_agg(t.data_object_code, t.value),
    '{}'::jsonb
)
from public.translation t
where t.language_code = _language_code
    and t.data_group = _data_group
    and t.data_object_code is not null
    and t.tenant_id = _tenant_id;
$$;

-- ============================================================================
-- search_translations
-- ============================================================================
create or replace function public.search_translations(
    _user_id bigint,
    _correlation_id text,
    _display_language_code text DEFAULT 'en',
    _search_text text DEFAULT null,
    _language_code text DEFAULT null,
    _data_group text DEFAULT null,
    _data_object_code text DEFAULT null,
    _data_object_id bigint DEFAULT null,
    _page integer DEFAULT 1,
    _page_size integer DEFAULT 10,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __translation_id integer,
        __language_code text,
        __language_value text,
        __data_group text,
        __data_object_code text,
        __data_object_id bigint,
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
                and (helpers.is_empty_string(__search_text)
                    or t.ua_search_data like '%' || __search_text || '%')
            order by t.data_group, t.data_object_code, t.language_code
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select t.translation_id
             , t.language_code
             , l.value as language_value
             , t.data_group
             , t.data_object_code
             , t.data_object_id
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
