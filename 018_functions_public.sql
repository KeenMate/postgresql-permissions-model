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
create or replace function public.create_journal_message(
    _created_by text,
    _user_id bigint,
    _event_id integer,
    _keys jsonb default null,
    _payload jsonb default null,
    _tenant_id integer default 1
) returns setof journal
    rows 1
    language plpgsql
as
$$
begin
    return query
        insert into journal (created_by, user_id, event_id, keys, data_payload, tenant_id)
        values (_created_by, _user_id, _event_id, _keys, _payload, _tenant_id)
        returning *;
end;
$$;

-- Overload: Accept event code as text, resolve to ID
create or replace function public.create_journal_message(
    _created_by text,
    _user_id bigint,
    _event_code text,
    _keys jsonb default null,
    _payload jsonb default null,
    _tenant_id integer default 1
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
            _created_by, _user_id, __event_id, _keys, _payload, _tenant_id
        );
end;
$$;

-- Convenience: Single entity key (entity_type + entity_id)
create or replace function public.create_journal_message(
    _created_by text,
    _user_id bigint,
    _event_id integer,
    _entity_type text,
    _entity_id bigint,
    _payload jsonb default null,
    _tenant_id integer default 1
) returns setof journal
    rows 1
    language sql
as
$$
select * from create_journal_message(
    _created_by, _user_id, _event_id,
    jsonb_build_object(_entity_type, _entity_id),
    _payload, _tenant_id
);
$$;

-- Convenience: Single entity with event code as text
create or replace function public.create_journal_message(
    _created_by text,
    _user_id bigint,
    _event_code text,
    _entity_type text,
    _entity_id bigint,
    _payload jsonb default null,
    _tenant_id integer default 1
) returns setof journal
    rows 1
    language sql
as
$$
select * from create_journal_message(
    _created_by, _user_id, _event_code,
    jsonb_build_object(_entity_type, _entity_id),
    _payload, _tenant_id
);
$$;

create or replace function public.get_journal_entry(_user_id bigint, _tenant_id integer, _journal_id bigint)
    returns table(
        __journal_id bigint,
        __event_id integer,
        __event_code text,
        __event_category text,
        __message text,
        __keys jsonb,
        __payload jsonb,
        __created_at timestamptz,
        __created_by text
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, 'journal.read_journal', _tenant_id);

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
             , j.created_at
             , j.created_by
        from journal j
        left join const.event_code ec on ec.event_id = j.event_id
        where j.tenant_id = _tenant_id
          and j.journal_id = _journal_id;
end;
$$;

-- Legacy alias
create or replace function public.get_journal_payload(_user_id bigint, _tenant_id integer, _journal_id bigint)
    returns TABLE(__journal_id bigint, __payload text)
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, 'journal.read_journal', _tenant_id);

    return query
        select journal_id, data_payload::text
        from journal
        where tenant_id = _tenant_id
          and journal_id = _journal_id;
end;
$$;

create or replace function public.validate_token(_updated_by text, _user_id bigint, _target_user_id bigint, _token_uid text, _token text, _token_type text, _ip_address text, _user_agent text, _origin text, _set_as_used boolean DEFAULT false)
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
		auth.has_permission(_user_id, 'tokens.validate_token');

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

	perform
		add_journal_msg(_updated_by, _user_id
			, format('User: %s validated a token for user: %s'
											, _updated_by, _target_user_id)
			, 'token', __token_id
			, array ['ip_address', _ip_address, 'user_agent', _user_agent, 'origin', _origin]
			, 50402
			, _tenant_id := 1);


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
			from auth.set_token_as_used(_updated_by, _user_id, __token_uid, _token,
																	_token_type, _ip_address, _user_agent,
																	_origin) used_token;
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
    _search_text text default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _target_user_id bigint default null,
    _event_id integer default null,
    _event_category text default null,
    _keys_criteria jsonb default null,
    _payload_criteria jsonb default null,
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
        __created_at timestamptz,
        __created_by text,
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
    __can_read_global_journal = auth.has_permission(_user_id, 'journal.read_global_journal', _throw_err := false);

    if (_tenant_id = 1) then
        if not __can_read_global_journal then
            perform auth.throw_no_permission(_user_id, 'journal.read_global_journal');
        end if;
    else
        perform auth.has_permission(_user_id, 'journal.read_journal', _tenant_id);
    end if;

    __normalized_search := helpers.normalize_text(_search_text);

    return query
        with filtered_rows as (
            select j.journal_id
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
             , j.created_at
             , j.created_by
             , fr.total_items
        from filtered_rows fr
        inner join journal j on fr.journal_id = j.journal_id
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
    _msg,
    _data_group,
    _data_object_id,
    case when _payload is null then null else jsonb_object(_payload) end,
    _event_id,
    _data_object_code,
    _tenant_id
);
$$;

-- Legacy alias for backwards compatibility
create or replace function public.search_journal_msgs(
    _user_id bigint,
    _search_text text,
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

