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
    value            text                                             not null,
    nrm_search_data   text,
    ts_search_data   tsvector,
    constraint translation_created_by_check check (length(created_by) <= 250),
    constraint translation_updated_by_check check (length(updated_by) <= 250)
);

create unique index uq_translation_code
    on public.translation (language_code, data_group, data_object_code)
    where data_object_code is not null;

create unique index uq_translation_id
    on public.translation (language_code, data_group, data_object_id)
    where data_object_id is not null;

create index ix_translation_ts_search
    on public.translation using gin (ts_search_data);

create index ix_translation_nrm_search
    on public.translation using gin (nrm_search_data gin_trgm_ops);

create index ix_translation_group
    on public.translation (data_group, language_code);

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

INSERT INTO const.event_category (category_code, title, range_start, range_end, is_error) VALUES
    ('language_event',    'Language Events',    20001, 20999, false),
    ('translation_event', 'Translation Events', 21001, 21999, false),
    ('language_error',    'Language/Translation Errors', 37001, 37999, true)
ON CONFLICT DO NOTHING;

INSERT INTO const.event_code (event_id, code, category_code, title, description, is_system) VALUES
    -- Language events (20001-20999)
    (20001, 'language_created',      'language_event',    'Language Created',      'New language was created', true),
    (20002, 'language_updated',      'language_event',    'Language Updated',      'Language was updated', true),
    (20003, 'language_deleted',      'language_event',    'Language Deleted',      'Language was deleted', true),

    -- Translation events (21001-21999)
    (21001, 'translation_created',   'translation_event', 'Translation Created',   'New translation was created', true),
    (21002, 'translation_updated',   'translation_event', 'Translation Updated',   'Translation was updated', true),
    (21003, 'translation_deleted',   'translation_event', 'Translation Deleted',   'Translation was deleted', true),
    (21004, 'translations_copied',   'translation_event', 'Translations Copied',   'Translations were copied between languages', true),

    -- Language/Translation errors (37001-37999)
    (37001, 'err_language_not_found',    'language_error', 'Language Not Found',    'Language does not exist', true),
    (37002, 'err_translation_not_found', 'language_error', 'Translation Not Found', 'Translation does not exist', true)
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
