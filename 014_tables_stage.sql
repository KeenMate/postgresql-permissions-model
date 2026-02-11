/*
 * Stage Schema Tables
 * ===================
 *
 * Staging tables for data imports and synchronization
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create table stage.external_group_member
(
    created_at               timestamp with time zone default now()           not null,
    created_by               text                     default 'unknown'::text not null,
    external_group_member_id bigint generated always as identity primary key,
    user_group_id            integer not null references auth.user_group on delete cascade,
    user_group_mapping_id    integer not null references auth.user_group_mapping on delete cascade,
    member_upn               text    not null,
    member_display_name      text    not null,
    member_email             text,
    constraint external_group_member_created_by_check check (length(created_by) <= 250)
);

create unique index uq_external_group_member
    on stage.external_group_member (user_group_mapping_id, member_upn);

/*
 * Journal Table
 * =============
 *
 * Audit logging table for all system events.
 * Message templates are stored in const.event_message and resolved at display time.
 *
 * Multi-Key Support:
 * The `keys` column stores entity references: {"order": 3, "item": 5, "customer": "C-123"}
 *
 * Data Payload:
 * The `data_payload` column stores values for message template placeholders and extra data.
 * Example: {"username": "john", "email": "john@example.com"}
 *
 * Message Resolution:
 * Template from event_message: 'User "{username}" created'
 * + data_payload: {"username": "john"}
 * = Display: 'User "john" created'
 */

create table public.journal
(
    created_at   timestamp with time zone default now()           not null,
    created_by   text                     default 'unknown'::text not null,
    journal_id   bigint generated always as identity primary key,
    tenant_id    integer references auth.tenant,
    event_id     integer not null references const.event_code,
    user_id      bigint references auth.user_info on delete set null,
    keys         jsonb,
    data_payload jsonb,
    constraint journal_created_by_check check (length(created_by) <= 250)
);

comment on column public.journal.keys is 'Entity references: {"order": 3, "item": 5}';
comment on column public.journal.data_payload is 'Template values and extra data: {"username": "john"}';

create index ix_journal_keys
    on public.journal using gin (keys);

create index ix_journal_payload
    on public.journal using gin (data_payload);

create index ix_journal_tenant_event
    on public.journal (tenant_id, event_id);

create index ix_journal_created
    on public.journal (created_at desc);

