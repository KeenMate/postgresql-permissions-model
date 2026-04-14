/*
 * Language & Translation Tables
 * =============================
 *
 * Language registry (const.language) and translation storage (public.translation)
 * with full-text search support, trigger infrastructure, seed data, FK constraints,
 * error functions, event codes, and permission seeding.
 *
 * Language/Translation Event Ranges:
 * - 20001-20999: Language events (informational)
 * - 21001-21999: Translation events (informational)
 * - 37001-37999: Language/Translation errors
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Tables
-- ============================================================================

create table const.language
(
    created_at                   timestamp with time zone default now()           not null,
    created_by                   text                     default 'unknown'::text not null,
    updated_at                   timestamp with time zone default now()           not null,
    updated_by                   text                     default 'unknown'::text not null,
    code                         text                                             not null
        primary key,
    value                        text                                             not null,
    tenant_id                    integer default 1                                not null
        references auth.tenant,
    is_frontend_language         boolean default false                            not null,
    is_backend_language          boolean default false                            not null,
    is_communication_language    boolean default false                            not null,
    frontend_logical_order       integer default 0                                not null,
    backend_logical_order        integer default 0                                not null,
    communication_logical_order  integer default 0                                not null,
    is_default_frontend          boolean default false                            not null,
    is_default_backend           boolean default false                            not null,
    is_default_communication     boolean default false                            not null,
    custom_data                  jsonb,
    constraint language_created_by_check check (length(created_by) <= 250),
    constraint language_updated_by_check check (length(updated_by) <= 250)
);

create table public.translation
(
    created_at       timestamp with time zone default now()           not null,
    created_by       text                     default 'unknown'::text not null,
    updated_at       timestamp with time zone default now()           not null,
    updated_by       text                     default 'unknown'::text not null,
    translation_id   integer generated always as identity
        primary key,
    language_code    text                                             not null
        references const.language (code) on delete cascade,
    tenant_id        integer default 1                                not null
        references auth.tenant,
    data_group       text                                             not null,
    data_object_code text,
    data_object_id   bigint,
    context          text                                             not null default 'text',
    value            text                                             not null,
    nrm_search_data   text,
    ts_search_data   tsvector,
    constraint translation_created_by_check check (length(created_by) <= 250),
    constraint translation_updated_by_check check (length(updated_by) <= 250)
);

create unique index uq_translation_code
    on public.translation (language_code, data_group, data_object_code, context)
    where data_object_code is not null;

create unique index uq_translation_id
    on public.translation (language_code, data_group, data_object_id, context)
    where data_object_id is not null;

create index ix_translation_ts_search
    on public.translation using gin (ts_search_data);

create index ix_translation_nrm_search
    on public.translation using gin (nrm_search_data ext.gin_trgm_ops);

create index ix_translation_group
    on public.translation (data_group, language_code);

-- ============================================================================
-- Materialized View: pre-aggregated translations (one row per object)
-- ============================================================================
-- Read path: single index probe, all contexts as jsonb.
-- Write path: INSERT/UPDATE the flat translation table, then refresh.
--
-- Output: {"title": "Folder", "description": "A folder resource"}
-- Usage:  mv.values->>'title', mv.values->>'description'
--
create materialized view if not exists public.mv_translation as
select t.language_code,
       t.tenant_id,
       t.data_group,
       t.data_object_code,
       t.data_object_id,
       jsonb_object_agg(t.context, t.value) as values
from public.translation t
group by t.language_code, t.tenant_id, t.data_group, t.data_object_code, t.data_object_id;

create unique index if not exists uq_mv_translation_code
    on public.mv_translation (language_code, data_group, data_object_code)
    where data_object_code is not null;

create unique index if not exists uq_mv_translation_id
    on public.mv_translation (language_code, data_group, data_object_id)
    where data_object_id is not null;

create index if not exists ix_mv_translation_group
    on public.mv_translation (data_group, language_code);

-- Refresh function (CONCURRENTLY = non-blocking, requires unique index)
create or replace function internal.refresh_translation_cache()
returns void
    language plpgsql
as
$$
begin
    -- CONCURRENTLY requires unique index and at least one prior populate.
    -- First call after CREATE MATERIALIZED VIEW uses non-concurrent refresh;
    -- subsequent calls use CONCURRENTLY for non-blocking behavior.
    begin
        refresh materialized view concurrently public.mv_translation;
    exception when others then
        refresh materialized view public.mv_translation;
    end;
end;
$$;

-- ============================================================================
-- Trigger Infrastructure
-- ============================================================================

create or replace function helpers.calculate_ts_regconfig(_language_code text) returns regconfig
    immutable
    parallel safe
    cost 1
    language sql
as
$$
select case lower(left(_language_code, 2))
    when 'en' then 'english'::regconfig
    when 'de' then 'german'::regconfig
    when 'fr' then 'french'::regconfig
    when 'es' then 'spanish'::regconfig
    when 'it' then 'italian'::regconfig
    when 'pt' then 'portuguese'::regconfig
    when 'nl' then 'dutch'::regconfig
    when 'da' then 'danish'::regconfig
    when 'fi' then 'finnish'::regconfig
    when 'hu' then 'hungarian'::regconfig
    when 'no' then 'norwegian'::regconfig
    when 'ro' then 'romanian'::regconfig
    when 'ru' then 'russian'::regconfig
    when 'sv' then 'swedish'::regconfig
    when 'tr' then 'turkish'::regconfig
    else 'simple'::regconfig
end;
$$;

create or replace function triggers.calculate_translation_fields() returns trigger
    language plpgsql
as
$$
begin
    if tg_op = 'INSERT' or tg_op = 'UPDATE' then
        new.nrm_search_data = helpers.normalize_text(new.value);
        new.ts_search_data = to_tsvector(helpers.calculate_ts_regconfig(new.language_code), new.value);
        return new;
    end if;
end;
$$;

create trigger trg_calculate_translation
    before insert or update
    on public.translation
    for each row
execute function triggers.calculate_translation_fields();

-- ============================================================================
-- Seed Data
-- ============================================================================

-- Default language
INSERT INTO const.language (created_by, updated_by, code, value, is_frontend_language, is_backend_language,
    is_communication_language, is_default_frontend, is_default_backend, is_default_communication,
    frontend_logical_order, backend_logical_order, communication_logical_order)
VALUES ('system', 'system', 'en', 'English', true, true, true, true, true, true, 1, 1, 1)
ON CONFLICT DO NOTHING;

-- FK: event_message.language_code -> const.language.code
ALTER TABLE const.event_message
    ADD CONSTRAINT fk_event_message_language
    FOREIGN KEY (language_code) REFERENCES const.language(code);

-- ============================================================================
-- Error Functions (37001-37999)
-- ============================================================================

-- 37001: Language not found
create or replace function error.raise_37001(_language_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Language (code: %) does not exist', _language_code
        using errcode = '37001';
end;
$$;

-- 37002: Translation not found
create or replace function error.raise_37002(_translation_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'Translation (id: %) does not exist', _translation_id
        using errcode = '37002';
end;
$$;

-- ============================================================================
-- Event Categories & Codes
-- ============================================================================

INSERT INTO const.event_category (category_code, range_start, range_end, is_error) VALUES
    ('language_event',    20001, 20999, false),
    ('translation_event', 21001, 21999, false),
    ('language_error',    37001, 37999, true)
ON CONFLICT DO NOTHING;

INSERT INTO const.event_code (event_id, code, category_code, is_system) VALUES
    (20001, 'language_created',      'language_event',    true),
    (20002, 'language_updated',      'language_event',    true),
    (20003, 'language_deleted',      'language_event',    true),
    (21001, 'translation_created',   'translation_event', true),
    (21002, 'translation_updated',   'translation_event', true),
    (21003, 'translation_deleted',   'translation_event', true),
    (21004, 'translations_copied',   'translation_event', true),
    (37001, 'err_language_not_found',    'language_error', true),
    (37002, 'err_translation_not_found', 'language_error', true)
ON CONFLICT DO NOTHING;

-- Language/translation event translations
INSERT INTO public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) VALUES
    ('system', 'system', 'en', 'event_category', 'language_event',    'title', 'Language Events'),
    ('system', 'system', 'en', 'event_category', 'translation_event', 'title', 'Translation Events'),
    ('system', 'system', 'en', 'event_category', 'language_error',    'title', 'Language/Translation Errors'),
    ('system', 'system', 'en', 'event_code', 'language_created',      'title', 'Language Created'),
    ('system', 'system', 'en', 'event_code', 'language_created',      'description', 'New language was created'),
    ('system', 'system', 'en', 'event_code', 'language_updated',      'title', 'Language Updated'),
    ('system', 'system', 'en', 'event_code', 'language_updated',      'description', 'Language was updated'),
    ('system', 'system', 'en', 'event_code', 'language_deleted',      'title', 'Language Deleted'),
    ('system', 'system', 'en', 'event_code', 'language_deleted',      'description', 'Language was deleted'),
    ('system', 'system', 'en', 'event_code', 'translation_created',   'title', 'Translation Created'),
    ('system', 'system', 'en', 'event_code', 'translation_created',   'description', 'New translation was created'),
    ('system', 'system', 'en', 'event_code', 'translation_updated',   'title', 'Translation Updated'),
    ('system', 'system', 'en', 'event_code', 'translation_updated',   'description', 'Translation was updated'),
    ('system', 'system', 'en', 'event_code', 'translation_deleted',   'title', 'Translation Deleted'),
    ('system', 'system', 'en', 'event_code', 'translation_deleted',   'description', 'Translation was deleted'),
    ('system', 'system', 'en', 'event_code', 'translations_copied',   'title', 'Translations Copied'),
    ('system', 'system', 'en', 'event_code', 'translations_copied',   'description', 'Translations were copied between languages'),
    ('system', 'system', 'en', 'event_code', 'err_language_not_found',    'title', 'Language Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_language_not_found',    'description', 'Language does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_translation_not_found', 'title', 'Translation Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_translation_not_found', 'description', 'Translation does not exist')
ON CONFLICT DO NOTHING;

-- Event message templates
INSERT INTO const.event_message (event_id, language_code, message_template) VALUES
    (20001, 'en', 'Language "{language_code}" ({language_value}) was created by {actor}'),
    (20002, 'en', 'Language "{language_code}" was updated by {actor}'),
    (20003, 'en', 'Language "{language_code}" was deleted by {actor}'),
    (21001, 'en', 'Translation for "{data_group}.{data_object_code}" in language "{language_code}" was created by {actor}'),
    (21002, 'en', 'Translation (id: {translation_id}) was updated by {actor}'),
    (21003, 'en', 'Translation (id: {translation_id}) was deleted by {actor}'),
    (21004, 'en', 'Translations were copied from "{from_language}" to "{to_language}" by {actor}')
ON CONFLICT DO NOTHING;
