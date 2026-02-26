/*
 * Public Functions
 * ================
 *
 * Application-level public functions: version management, journal
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function public.start_version_update(_version text, _title text, _description text DEFAULT NULL::text, _component text DEFAULT 'main'::text) returns SETOF __version
    language sql
as
$$

insert into __version(component, version, title, description)
VALUES (_component, _version, _title, _description)
returning *;

$$;

create or replace function public.stop_version_update(_version text, _component text DEFAULT 'main'::text) returns SETOF __version
    language sql
as
$$

update __version
set execution_finished = now()
where component = _component
	and version = _version
returning *;

$$;

/*
 * Journal Functions
 * =================
 *
 * Message templates are stored in const.event_message.
 * The journal only stores event_id, keys, and data_payload.
 * Messages are resolved at display time using format_journal_message().
 *
 * Template placeholders use {key} syntax:
 *   Template: 'User "{username}" created by {actor}'
 *   Payload:  {"username": "john", "actor": "admin"}
 *   Result:   'User "john" created by admin'
 */

-- Helper: Build keys JSONB from key-value pairs
-- Usage: journal_keys('order', '3', 'item', '5') -> {"order": "3", "item": "5"}
create or replace function public.journal_keys(variadic _pairs text[])
    returns jsonb
    immutable
    language sql
as
$$
select jsonb_object(_pairs);
$$;

-- Format a message template with values from payload
-- Template: 'User "{username}" created'  +  {"username": "john"}  =  'User "john" created'
create or replace function public.format_journal_message(
    _template text,
    _payload jsonb,
    _created_by text default null
) returns text
    immutable
    language plpgsql
as
$$
declare
    __result text := _template;
    __key text;
    __value text;
begin
    if _payload is null then
        return __result;
    end if;

    -- Replace {key} placeholders with values from payload
    for __key, __value in select * from jsonb_each_text(_payload)
    loop
        __result := replace(__result, '{' || __key || '}', coalesce(__value, ''));
    end loop;

    -- Also replace {actor} with created_by if not in payload
    if _created_by is not null and position('{actor}' in __result) > 0 then
        __result := replace(__result, '{actor}', _created_by);
    end if;

    return __result;
end;
$$;

-- Get message template for an event in a specific language
create or replace function public.get_event_message_template(
    _event_id integer,
    _language_code text default 'en'
) returns text
    stable
    language sql
as
$$
select coalesce(
    -- Try requested language
    (select message_template from const.event_message
     where event_id = _event_id and language_code = _language_code and is_active = true),
    -- Fall back to English
    (select message_template from const.event_message
     where event_id = _event_id and language_code = 'en' and is_active = true),
    -- Fall back to event title
    (select title from const.event_code where event_id = _event_id)
);
$$;

-- Core function: Create journal entry with event ID
-- Respects journal level setting from const.sys_param (journal.level)
create or replace function public.create_journal_message(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_id integer,
    _keys jsonb default null,
    _payload jsonb default null,
    _tenant_id integer default 1,
    _request_context jsonb default null
) returns setof journal
    rows 1
    language plpgsql
as
$$
begin
    -- Check if we should log based on journal level and event type
    if not helpers.should_log_journal(helpers.is_event_read_only(_event_id)) then
        return;
    end if;

    return query
        insert into journal (created_by, user_id, correlation_id, event_id, keys, data_payload, tenant_id, request_context)
        values (_created_by, _user_id, _correlation_id, _event_id, _keys, _payload, _tenant_id, _request_context)
        returning *;
end;
$$;

-- Create journal entry with event code (text), resolve to ID
create or replace function public.create_journal_message_by_code(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_code text,
    _keys jsonb default null,
    _payload jsonb default null,
    _tenant_id integer default 1,
    _request_context jsonb default null
) returns setof journal
    rows 1
    language plpgsql
as
$$
declare
    __event_id integer;
begin
    select event_id into __event_id
    from const.event_code
    where code = _event_code;

    if __event_id is null then
        raise exception 'Event code "%" not found in const.event_code', _event_code
            using errcode = '22000';
    end if;

    return query
        select * from create_journal_message(
            _created_by, _user_id, _correlation_id, __event_id, _keys, _payload, _tenant_id, _request_context
        );
end;
$$;

-- Create journal entry for a single entity (entity_type + entity_id)
create or replace function public.create_journal_message_for_entity(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_id integer,
    _entity_type text,
    _entity_id bigint,
    _payload jsonb default null,
    _tenant_id integer default 1,
    _request_context jsonb default null
) returns setof journal
    rows 1
    language sql
as
$$
select * from create_journal_message(
    _created_by, _user_id, _correlation_id, _event_id,
    jsonb_build_object(_entity_type, _entity_id),
    _payload, _tenant_id, _request_context
);
$$;

-- Create journal entry for a single entity with event code as text
create or replace function public.create_journal_message_for_entity_by_code(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_code text,
    _entity_type text,
    _entity_id bigint,
    _payload jsonb default null,
    _tenant_id integer default 1,
    _request_context jsonb default null
) returns setof journal
    rows 1
    language sql
as
$$
select * from create_journal_message_by_code(
    _created_by, _user_id, _correlation_id, _event_code,
    jsonb_build_object(_entity_type, _entity_id),
    _payload, _tenant_id, _request_context
);
$$;

create or replace function public.get_journal_entry(_user_id bigint, _correlation_id text, _tenant_id integer, _journal_id bigint)
    returns table(
        __journal_id bigint,
        __event_id integer,
        __event_code text,
        __event_category text,
        __message text,
        __keys jsonb,
        __payload jsonb,
        __request_context jsonb,
        __created_at timestamptz,
        __created_by text,
        __correlation_id text
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'journal.read_journal', _tenant_id);

    return query
        select j.journal_id
             , j.event_id
             , ec.code
             , ec.category_code
             , format_journal_message(
                   get_event_message_template(j.event_id),
                   j.data_payload,
                   j.created_by
               )
             , j.keys
             , j.data_payload
             , j.request_context
             , j.created_at
             , j.created_by
             , j.correlation_id
        from journal j
        left join const.event_code ec on ec.event_id = j.event_id
        where j.tenant_id = _tenant_id
          and j.journal_id = _journal_id;
end;
$$;

-- Legacy alias
create or replace function public.get_journal_payload(_user_id bigint, _correlation_id text, _tenant_id integer, _journal_id bigint)
    returns TABLE(__journal_id bigint, __payload text)
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'journal.read_journal', _tenant_id);

    return query
        select journal_id, data_payload::text
        from journal
        where tenant_id = _tenant_id
          and journal_id = _journal_id;
end;
$$;

create or replace function public.validate_token(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _token_uid text, _token text, _token_type text, _request_context jsonb, _set_as_used boolean DEFAULT false)
    returns TABLE(___token_id bigint, ___token_uid text, ___token_state_code text, ___used_at timestamp with time zone, ___user_id bigint, ___user_oid text, ___token_data jsonb)
    language plpgsql
as
$$
declare
	__token_id         bigint;
	__token_uid        text;
	__token_state_code text;
	__token_user_id    bigint;
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tokens.validate_token');

	-- invalidate old tokens, this way we don't need a job to do that, every user will work for us this way
	perform unsecure.expire_tokens(_updated_by);

	select token_id, uid, token_state_code, user_id
	from auth.token
	where ((_target_user_id is not null and token.user_id = _target_user_id) or true)
		and token_type_code = _token_type
		and (helpers.is_not_empty_string(_token_uid) or helpers.is_not_empty_string(_token))
		and (helpers.is_empty_string(_token_uid) or uid = _token_uid)
		and (helpers.is_empty_string(_token) or token = _token)
	into __token_id, __token_uid, __token_state_code, __token_user_id;

	if
		__token_id is null then
		perform error.raise_52277();
	end if;

	if
		__token_state_code <> 'valid' then
		perform error.raise_52278(__token_uid);
	end if;

	if
		_target_user_id is not null and _target_user_id <> __token_user_id then
		perform error.raise_52279(__token_uid);
	end if;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 15002  -- token_used
			, 'token', __token_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1
			, _request_context);


	if
		_set_as_used then
		return query
			select used_token.__token_id
					 , used_token.__token_uid
					 , used_token.__token_state_code
					 , used_token.__used_at
					 , used_token.__user_id
					 , used_token.__user_oid
					 , used_token.__token_data
			from auth.set_token_as_used(_updated_by, _user_id, _correlation_id, __token_uid, _token,
																	_token_type, _request_context) used_token;
	else
		return query
			select token_id, uid, token_state_code, used_at, user_id, user_oid, token_data
			from auth.token
			where token_id = __token_id;
	end if;
end;
$$;

create or replace function public.check_version(_version text, _component text DEFAULT 'main'::text, _throw_err boolean DEFAULT false) returns boolean
    cost 1
    language plpgsql
as
$$
declare
	__result bool;
begin

	select exists(select
								from __version
								where component = _component
									and version = _version)
	into __result;
  
	if _throw_err and not __result then
		raise exception 'Version: % of component: % not found', _version, _component;
	else
		return __result;
	end if;
end;
$$;

create or replace function public.get_version(_component text DEFAULT 'main'::text, _version text DEFAULT NULL::text)
    returns TABLE(__version_id integer, __version text, __title text, __execution_started timestamp with time zone, __execution_finished timestamp with time zone)
    cost 1
    language sql
as
$$
select v.version_id, v.version, v.title, v.execution_started, execution_finished
from __version v
where component = _component
	and ((_version is not null and version = _version)
	or (version_id in (select version_id
										 from __version
										 where component = _component
										 order by execution_started desc
										 limit 1)));
$$;

/*
 * Search journal messages
 *
 * Supports filtering by:
 * - _search_text: Full-text search in data_payload JSONB
 * - _event_category: Filter by category (e.g., 'user_event', 'group_event')
 * - _event_id: Filter by specific event ID
 * - _keys_criteria: Filter by keys using JSONB containment (e.g., '{"order": 3}')
 * - _payload_criteria: Filter by payload using JSONB containment
 */
create or replace function public.search_journal(
    _user_id bigint,
    _correlation_id text default null,
    _search_text text default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _target_user_id bigint default null,
    _event_id integer default null,
    _event_category text default null,
    _keys_criteria jsonb default null,
    _payload_criteria jsonb default null,
    _request_context_criteria jsonb default null,
    _page integer default 1,
    _page_size integer default 10,
    _tenant_id integer default 1
)
    returns table(
        __journal_id bigint,
        __event_id integer,
        __event_code text,
        __event_category text,
        __user_id bigint,
        __message text,
        __keys jsonb,
        __request_context jsonb,
        __created_at timestamptz,
        __created_by text,
        __correlation_id text,
        __total_items bigint
    )
    stable
    language plpgsql
as
$$
declare
    __can_read_global_journal bool;
    __normalized_search text;
begin
    __can_read_global_journal = auth.has_permission(_user_id, _correlation_id, 'journal.read_global_journal', _throw_err := false);

    if (_tenant_id = 1) then
        if not __can_read_global_journal then
            perform internal.throw_no_permission(_user_id, 'journal.read_global_journal');
        end if;
    else
        perform auth.has_permission(_user_id, _correlation_id, 'journal.read_journal', _tenant_id);
    end if;

    __normalized_search := helpers.normalize_text(_search_text);

    return query
        with filtered_rows as (
            select j.journal_id
                 , j.created_at as journal_created_at
                 , count(1) over () as total_items
            from journal j
            left join const.event_code ec on ec.event_id = j.event_id
            where (helpers.is_empty_string(__normalized_search) or
                   j.data_payload::text ilike '%' || __normalized_search || '%')
              and ((_tenant_id = 1 and __can_read_global_journal) or j.tenant_id = _tenant_id)
              and (_target_user_id is null or j.user_id = _target_user_id)
              and (_event_id is null or j.event_id = _event_id)
              and (_event_category is null or ec.category_code = _event_category)
              and (_keys_criteria is null or j.keys @> _keys_criteria)
              and (_payload_criteria is null or j.data_payload @> _payload_criteria)
              and (_request_context_criteria is null or j.request_context @> _request_context_criteria)
              and (_correlation_id is null or j.correlation_id = _correlation_id)
              and j.created_at between coalesce(_from, now() - interval '100 years')
                                   and coalesce(_to, now() + interval '100 years')
            order by j.created_at desc
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select j.journal_id
             , j.event_id
             , ec.code
             , ec.category_code
             , j.user_id
             , format_journal_message(
                   get_event_message_template(j.event_id),
                   j.data_payload,
                   j.created_by
               )
             , j.keys
             , j.request_context
             , j.created_at
             , j.created_by
             , j.correlation_id
             , fr.total_items
        from filtered_rows fr
        inner join journal j on fr.journal_id = j.journal_id and j.created_at = fr.journal_created_at
        left join const.event_code ec on ec.event_id = j.event_id
        order by j.created_at desc;
end;
$$;

/*
 * Legacy Journal Functions
 * ========================
 *
 * These wrapper functions maintain backwards compatibility with old add_journal_msg calls.
 * New code should use create_journal_message() directly.
 *
 * Old columns mapped to new structure:
 * - _msg (message) -> Ignored (resolved from event_message template at display time)
 * - _data_group + _data_object_id -> keys JSONB: {"<data_group>": <data_object_id>}
 * - _data_object_code -> Added to keys if provided
 * - _payload -> data_payload JSONB
 * - _event_id -> event_id (required for message template resolution)
 */

-- Legacy: add_journal_msg_jsonb with full parameter set
create or replace function public.add_journal_msg_jsonb(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _msg text,
    _data_group text default 'system',
    _data_object_id bigint default null,
    _payload jsonb default null,
    _event_id integer default null,
    _data_object_code text default null,
    _tenant_id integer default 1
) returns setof journal
    rows 1
    language plpgsql
as
$$
declare
    __keys jsonb;
    __payload jsonb;
    __actual_event_id integer;
begin
    -- Build keys from legacy data_group/data_object_id/data_object_code
    __keys := case
        when _data_object_id is not null then jsonb_build_object(_data_group, _data_object_id)
        when _data_object_code is not null then jsonb_build_object(_data_group, _data_object_code)
        else null
    end;

    -- Merge any additional payload, preserving legacy message for debugging
    __payload := coalesce(_payload, '{}'::jsonb);
    if _msg is not null then
        __payload := __payload || jsonb_build_object('_legacy_msg', _msg);
    end if;

    -- Use event_id if provided, otherwise default to a generic event
    __actual_event_id := coalesce(_event_id, 10002); -- default to user_updated

    return query
        select * from create_journal_message(
            _created_by,
            _user_id,
            _correlation_id,
            __actual_event_id,
            __keys,
            __payload,
            _tenant_id
        );
end;
$$;

-- Legacy: add_journal_msg with text[] payload (converts to jsonb)
create or replace function public.add_journal_msg(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _msg text,
    _data_group text default 'system',
    _data_object_id bigint default null,
    _payload text[] default null,
    _event_id integer default null,
    _data_object_code text default null,
    _tenant_id integer default 1
) returns setof journal
    rows 1
    language sql
as
$$
select * from add_journal_msg_jsonb(
    _created_by,
    _user_id,
    _correlation_id,
    _msg,
    _data_group,
    _data_object_id,
    case when _payload is null then null else jsonb_object(_payload) end,
    _event_id,
    _data_object_code,
    _tenant_id
);
$$;

/*
 * Event Code Management Functions
 * ================================
 *
 * CRUD functions for managing event categories, codes, and messages at runtime.
 * System events (is_system = true) are protected from deletion.
 * Application-specific events should use the 50000+ range.
 */

-- Create a new event category
create or replace function public.create_event_category(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _category_code text,
    _title text,
    _range_start integer,
    _range_end integer,
    _is_error boolean default false,
    _source text default null
) returns setof const.event_category
    rows 1
    language plpgsql
as
$$
begin
    insert into const.event_category (category_code, title, range_start, range_end, is_error, source)
    values (_category_code, _title, _range_start, _range_end, _is_error, _source);

    return query
        select *
        from const.event_category
        where category_code = _category_code;
end;
$$;

-- Create a new event code
create or replace function public.create_event_code(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_id integer,
    _code text,
    _category_code text,
    _title text,
    _description text default null,
    _is_read_only boolean default false,
    _source text default null
) returns setof const.event_code
    rows 1
    language plpgsql
as
$$
declare
    __range_start integer;
    __range_end integer;
begin
    -- Validate category exists
    select range_start, range_end
    into __range_start, __range_end
    from const.event_category
    where category_code = _category_code;

    if __range_start is null then
        perform error.raise_31014(_category_code);
    end if;

    -- Validate event_id is within the category's range
    if _event_id < __range_start or _event_id > __range_end then
        perform error.raise_31013(_event_id, _category_code, __range_start, __range_end);
    end if;

    -- Always insert with is_system = false (system events come from seed only)
    insert into const.event_code (event_id, code, category_code, title, description, is_read_only, is_system, source)
    values (_event_id, _code, _category_code, _title, _description, _is_read_only, false, _source);

    return query
        select *
        from const.event_code
        where event_id = _event_id;
end;
$$;

-- Create a new event message template
create or replace function public.create_event_message(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _event_id integer,
    _message_template text,
    _language_code text default 'en'
) returns setof const.event_message
    rows 1
    language plpgsql
as
$$
begin
    -- Validate event_code exists
    if not exists (select 1 from const.event_code where event_id = _event_id) then
        perform error.raise_31011(_event_id);
    end if;

    insert into const.event_message (created_by, updated_by, event_id, language_code, message_template)
    values (_created_by, _created_by, _event_id, _language_code, _message_template);

    return query
        select *
        from const.event_message
        where event_id = _event_id
          and language_code = _language_code
          and is_active = true;
end;
$$;

-- Delete an event code (system events are protected)
create or replace function public.delete_event_code(
    _deleted_by text,
    _user_id bigint,
    _correlation_id text,
    _event_id integer
) returns void
    language plpgsql
as
$$
declare
    __is_system boolean;
begin
    -- Check event code exists and get is_system flag
    select is_system
    into __is_system
    from const.event_code
    where event_id = _event_id;

    if __is_system is null then
        perform error.raise_31011(_event_id);
    end if;

    -- Protect system events
    if __is_system then
        perform error.raise_31010(_event_id);
    end if;

    -- Cascade: delete related event messages
    delete from const.event_message where event_id = _event_id;

    -- Delete the event code
    delete from const.event_code where event_id = _event_id;
end;
$$;

-- Delete an event category (must have no event codes)
create or replace function public.delete_event_category(
    _deleted_by text,
    _user_id bigint,
    _correlation_id text,
    _category_code text
) returns void
    language plpgsql
as
$$
begin
    -- Check category exists
    if not exists (select 1 from const.event_category where category_code = _category_code) then
        perform error.raise_31014(_category_code);
    end if;

    -- Check no system events belong to this category
    if exists (select 1 from const.event_code where category_code = _category_code and is_system = true) then
        perform error.raise_31010(
            (select event_id from const.event_code where category_code = _category_code and is_system = true limit 1)
        );
    end if;

    -- Check no event codes reference it
    if exists (select 1 from const.event_code where category_code = _category_code) then
        perform error.raise_31012(_category_code);
    end if;

    -- Delete the category
    delete from const.event_category where category_code = _category_code;
end;
$$;

-- Delete an event message (system event messages are protected)
create or replace function public.delete_event_message(
    _deleted_by text,
    _user_id bigint,
    _correlation_id text,
    _event_message_id integer
) returns void
    language plpgsql
as
$$
declare
    __event_id integer;
    __is_system boolean;
begin
    -- Get the parent event_id
    select event_id
    into __event_id
    from const.event_message
    where event_message_id = _event_message_id;

    if __event_id is null then
        perform error.raise_31011(0);
    end if;

    -- Check parent event_code is_system
    select is_system
    into __is_system
    from const.event_code
    where event_id = __event_id;

    if __is_system then
        perform error.raise_31010(__event_id);
    end if;

    -- Delete the message
    delete from const.event_message where event_message_id = _event_message_id;
end;
$$;

-- Legacy alias for backwards compatibility
create or replace function public.search_journal_msgs(
    _user_id bigint,
    _correlation_id text default null,
    _search_text text default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _target_user_id integer default null,
    _event_id integer default null,
    _data_group text default null,
    _data_object_id bigint default null,
    _data_object_code text default null,
    _payload_criteria jsonb default null,
    _page integer default 1,
    _page_size integer default 10,
    _tenant_id integer default 1
)
    returns table(
        __created timestamptz,
        __created_by text,
        __journal_id bigint,
        __event_id integer,
        __data_group text,
        __data_object_id bigint,
        __data_object_code text,
        __user_id bigint,
        __msg text,
        __total_items bigint
    )
    stable
    language plpgsql
as
$$
begin
    -- Map old parameters to new keys-based search
    return query
        select sj.__created_at
             , sj.__created_by
             , sj.__journal_id
             , sj.__event_id
             , _data_group  -- Return the filter value since we don't store it anymore
             , _data_object_id
             , _data_object_code
             , sj.__user_id
             , sj.__message
             , sj.__total_items
        from search_journal(
            _user_id,
            _correlation_id,
            _search_text,
            _from,
            _to,
            _target_user_id,
            _event_id,
            null,  -- _event_category
            case
                when _data_object_id is not null then jsonb_build_object(_data_group, _data_object_id)
                when _data_object_code is not null then jsonb_build_object(_data_group, _data_object_code)
                else null
            end,
            _payload_criteria,
            _page,
            _page_size,
            _tenant_id
        ) sj;
end;
$$;

/*
 * Purge Audit Data
 * ================
 *
 * Purges old journal entries and user events based on retention policy.
 * Requires 'journal.purge_journal' permission.
 */
create or replace function public.purge_audit_data(
    _deleted_by text, _user_id bigint, _correlation_id text,
    _older_than_days integer default null
) returns table(__journal_deleted bigint, __user_events_deleted bigint)
    language plpgsql
as
$$
declare
    __j_deleted bigint;
    __ue_deleted bigint;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'journal.purge_journal');

    select __deleted_count from unsecure.purge_journal(_deleted_by, _user_id, _correlation_id, _older_than_days)
    into __j_deleted;

    select __deleted_count from unsecure.purge_user_events(_deleted_by, _user_id, _correlation_id, _older_than_days)
    into __ue_deleted;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 17001  -- audit_data_purged
        , 'system', 0
        , jsonb_build_object('journal_deleted', __j_deleted, 'user_events_deleted', __ue_deleted,
            'older_than_days', coalesce(_older_than_days, -1))
        , 1);

    return query select __j_deleted, __ue_deleted;
end;
$$;

