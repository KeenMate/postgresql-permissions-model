/*
 * Language Functions
 * ==================
 *
 * CRUD and query functions for const.language
 *
 * Functions:
 * - public.create_language       - Create a new language (20001)
 * - public.update_language       - Update an existing language (20002)
 * - public.delete_language       - Delete a language (20003)
 * - public.get_language          - Get single language by code
 * - public.get_languages         - Get all languages with optional filters
 * - public.get_frontend_languages       - Get frontend languages ordered
 * - public.get_backend_languages        - Get backend languages ordered
 * - public.get_communication_languages  - Get communication languages ordered
 * - public.get_default_language         - Get default language for a category
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- create_language
-- ============================================================================
create or replace function public.create_language(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _code text,
    _value text,
    _is_frontend_language boolean DEFAULT false,
    _is_backend_language boolean DEFAULT false,
    _is_communication_language boolean DEFAULT false,
    _frontend_logical_order integer DEFAULT 0,
    _backend_logical_order integer DEFAULT 0,
    _communication_logical_order integer DEFAULT 0,
    _is_default_frontend boolean DEFAULT false,
    _is_default_backend boolean DEFAULT false,
    _is_default_communication boolean DEFAULT false,
    _custom_data jsonb DEFAULT null,
    _tenant_id integer DEFAULT 1
)
    returns setof const.language
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'languages.create_language', _tenant_id);

    -- Unset other defaults when setting this as default
    if _is_default_frontend then
        update const.language set is_default_frontend = false, updated_by = _created_by, updated_at = now()
        where is_default_frontend = true and tenant_id = _tenant_id;
    end if;
    if _is_default_backend then
        update const.language set is_default_backend = false, updated_by = _created_by, updated_at = now()
        where is_default_backend = true and tenant_id = _tenant_id;
    end if;
    if _is_default_communication then
        update const.language set is_default_communication = false, updated_by = _created_by, updated_at = now()
        where is_default_communication = true and tenant_id = _tenant_id;
    end if;

    return query
        insert into const.language (created_by, updated_by, code, value, tenant_id,
            is_frontend_language, is_backend_language, is_communication_language,
            frontend_logical_order, backend_logical_order, communication_logical_order,
            is_default_frontend, is_default_backend, is_default_communication, custom_data)
        values (_created_by, _created_by, _code, _value, _tenant_id,
            _is_frontend_language, _is_backend_language, _is_communication_language,
            _frontend_logical_order, _backend_logical_order, _communication_logical_order,
            _is_default_frontend, _is_default_backend, _is_default_communication, _custom_data)
        returning *;

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 20001  -- language_created
        , null::jsonb  -- keys
        , jsonb_strip_nulls(jsonb_build_object(
            'language_code', _code, 'language_value', _value,
            'is_frontend_language', _is_frontend_language,
            'is_backend_language', _is_backend_language,
            'is_communication_language', _is_communication_language))
        , _tenant_id);
end;
$$;

-- ============================================================================
-- update_language
-- ============================================================================
create or replace function public.update_language(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _code text,
    _value text DEFAULT null,
    _is_frontend_language boolean DEFAULT null,
    _is_backend_language boolean DEFAULT null,
    _is_communication_language boolean DEFAULT null,
    _frontend_logical_order integer DEFAULT null,
    _backend_logical_order integer DEFAULT null,
    _communication_logical_order integer DEFAULT null,
    _is_default_frontend boolean DEFAULT null,
    _is_default_backend boolean DEFAULT null,
    _is_default_communication boolean DEFAULT null,
    _custom_data jsonb DEFAULT null,
    _tenant_id integer DEFAULT 1
)
    returns setof const.language
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'languages.update_language', _tenant_id);

    if not exists (select 1 from const.language where code = _code) then
        perform error.raise_37001(_code);
    end if;

    -- Unset other defaults when setting this as default
    if _is_default_frontend = true then
        update const.language set is_default_frontend = false, updated_by = _created_by, updated_at = now()
        where is_default_frontend = true and code <> _code and tenant_id = _tenant_id;
    end if;
    if _is_default_backend = true then
        update const.language set is_default_backend = false, updated_by = _created_by, updated_at = now()
        where is_default_backend = true and code <> _code and tenant_id = _tenant_id;
    end if;
    if _is_default_communication = true then
        update const.language set is_default_communication = false, updated_by = _created_by, updated_at = now()
        where is_default_communication = true and code <> _code and tenant_id = _tenant_id;
    end if;

    return query
        update const.language
        set updated_by                  = _created_by
          , updated_at                  = now()
          , value                       = coalesce(_value, value)
          , is_frontend_language        = coalesce(_is_frontend_language, is_frontend_language)
          , is_backend_language         = coalesce(_is_backend_language, is_backend_language)
          , is_communication_language   = coalesce(_is_communication_language, is_communication_language)
          , frontend_logical_order      = coalesce(_frontend_logical_order, frontend_logical_order)
          , backend_logical_order       = coalesce(_backend_logical_order, backend_logical_order)
          , communication_logical_order = coalesce(_communication_logical_order, communication_logical_order)
          , is_default_frontend         = coalesce(_is_default_frontend, is_default_frontend)
          , is_default_backend          = coalesce(_is_default_backend, is_default_backend)
          , is_default_communication    = coalesce(_is_default_communication, is_default_communication)
          , custom_data                 = coalesce(_custom_data, custom_data)
        where code = _code
        returning *;

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 20002  -- language_updated
        , null::jsonb  -- keys
        , jsonb_strip_nulls(jsonb_build_object('language_code', _code, 'language_value', _value))
        , _tenant_id);
end;
$$;

-- ============================================================================
-- delete_language
-- ============================================================================
create or replace function public.delete_language(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _code text,
    _tenant_id integer DEFAULT 1
)
    returns void
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'languages.delete_language', _tenant_id);

    if not exists (select 1 from const.language where code = _code) then
        perform error.raise_37001(_code);
    end if;

    -- CASCADE on translation FK handles cleanup
    delete from const.language where code = _code;

    perform create_journal_message(_created_by, _user_id, _correlation_id
        , 20003  -- language_deleted
        , null::jsonb  -- keys
        , jsonb_build_object('language_code', _code)
        , _tenant_id);
end;
$$;

-- ============================================================================
-- get_language
-- ============================================================================
create or replace function public.get_language(_code text)
    returns setof const.language
    stable
    rows 1
    language sql
as
$$
select * from const.language where code = _code;
$$;

-- ============================================================================
-- get_languages
-- ============================================================================
create or replace function public.get_languages(
    _display_language_code text DEFAULT 'en',
    _is_frontend boolean DEFAULT null,
    _is_backend boolean DEFAULT null,
    _is_communication boolean DEFAULT null,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __code text,
        __value text,
        __display_name text,
        __is_frontend_language boolean,
        __is_backend_language boolean,
        __is_communication_language boolean,
        __frontend_logical_order integer,
        __backend_logical_order integer,
        __communication_logical_order integer,
        __is_default_frontend boolean,
        __is_default_backend boolean,
        __is_default_communication boolean,
        __custom_data jsonb
    )
    stable
    rows 100
    language sql
as
$$
select l.code
     , l.value
     , coalesce(t.value, l.value) as display_name
     , l.is_frontend_language
     , l.is_backend_language
     , l.is_communication_language
     , l.frontend_logical_order
     , l.backend_logical_order
     , l.communication_logical_order
     , l.is_default_frontend
     , l.is_default_backend
     , l.is_default_communication
     , l.custom_data
from const.language l
left join public.translation t
    on t.language_code = _display_language_code
    and t.data_group = 'language'
    and t.data_object_code = l.code
    and t.tenant_id = _tenant_id
where l.tenant_id = _tenant_id
    and (_is_frontend is null or l.is_frontend_language = _is_frontend)
    and (_is_backend is null or l.is_backend_language = _is_backend)
    and (_is_communication is null or l.is_communication_language = _is_communication)
order by l.value;
$$;

-- ============================================================================
-- get_frontend_languages
-- ============================================================================
create or replace function public.get_frontend_languages(
    _display_language_code text DEFAULT 'en',
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __code text,
        __value text,
        __display_name text,
        __frontend_logical_order integer,
        __is_default_frontend boolean,
        __custom_data jsonb
    )
    stable
    rows 100
    language sql
as
$$
select l.code
     , l.value
     , coalesce(t.value, l.value) as display_name
     , l.frontend_logical_order
     , l.is_default_frontend
     , l.custom_data
from const.language l
left join public.translation t
    on t.language_code = _display_language_code
    and t.data_group = 'language'
    and t.data_object_code = l.code
    and t.tenant_id = _tenant_id
where l.is_frontend_language = true
    and l.tenant_id = _tenant_id
order by l.frontend_logical_order, l.value;
$$;

-- ============================================================================
-- get_backend_languages
-- ============================================================================
create or replace function public.get_backend_languages(
    _display_language_code text DEFAULT 'en',
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __code text,
        __value text,
        __display_name text,
        __backend_logical_order integer,
        __is_default_backend boolean,
        __custom_data jsonb
    )
    stable
    rows 100
    language sql
as
$$
select l.code
     , l.value
     , coalesce(t.value, l.value) as display_name
     , l.backend_logical_order
     , l.is_default_backend
     , l.custom_data
from const.language l
left join public.translation t
    on t.language_code = _display_language_code
    and t.data_group = 'language'
    and t.data_object_code = l.code
    and t.tenant_id = _tenant_id
where l.is_backend_language = true
    and l.tenant_id = _tenant_id
order by l.backend_logical_order, l.value;
$$;

-- ============================================================================
-- get_communication_languages
-- ============================================================================
create or replace function public.get_communication_languages(
    _display_language_code text DEFAULT 'en',
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __code text,
        __value text,
        __display_name text,
        __communication_logical_order integer,
        __is_default_communication boolean,
        __custom_data jsonb
    )
    stable
    rows 100
    language sql
as
$$
select l.code
     , l.value
     , coalesce(t.value, l.value) as display_name
     , l.communication_logical_order
     , l.is_default_communication
     , l.custom_data
from const.language l
left join public.translation t
    on t.language_code = _display_language_code
    and t.data_group = 'language'
    and t.data_object_code = l.code
    and t.tenant_id = _tenant_id
where l.is_communication_language = true
    and l.tenant_id = _tenant_id
order by l.communication_logical_order, l.value;
$$;

-- ============================================================================
-- get_default_language
-- ============================================================================
create or replace function public.get_default_language(
    _display_language_code text DEFAULT 'en',
    _is_frontend boolean DEFAULT null,
    _is_backend boolean DEFAULT null,
    _is_communication boolean DEFAULT null,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __code text,
        __value text,
        __display_name text,
        __custom_data jsonb
    )
    stable
    rows 1
    language sql
as
$$
select l.code
     , l.value
     , coalesce(t.value, l.value) as display_name
     , l.custom_data
from const.language l
left join public.translation t
    on t.language_code = _display_language_code
    and t.data_group = 'language'
    and t.data_object_code = l.code
    and t.tenant_id = _tenant_id
where l.tenant_id = _tenant_id
    and (_is_frontend is null or l.is_default_frontend = _is_frontend)
    and (_is_backend is null or l.is_default_backend = _is_backend)
    and (_is_communication is null or l.is_default_communication = _is_communication)
limit 1;
$$;
