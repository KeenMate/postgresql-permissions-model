/*
 * Auth API Key Functions
 * ======================
 *
 * API key management: create, validate, assign permissions
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.generate_api_key_username(_api_key text) returns text
    immutable
    cost 1
    language sql
as
$$
select 'api_key_' || _api_key;
$$;

create or replace function auth.generate_api_key() returns text
    cost 1
    language sql
as
$$
select ext.uuid_generate_v4()::text;
$$;

create or replace function auth.generate_api_secret() returns text
    cost 1
    language sql
as
$$
select ext.uuid_generate_v4()::text;
$$;

create or replace function auth.generate_api_secret_hash(_secret text) returns bytea
    immutable
    cost 1
    language sql
as
$$
select sha256(convert_to(_secret, 'UTF8')::bytea);
$$;

create or replace function auth.create_api_key(_created_by text, _user_id bigint, _correlation_id text, _title text, _description text, _perm_set_code text, _permission_codes text[], _api_key text DEFAULT NULL::text, _api_secret text DEFAULT NULL::text, _expire_at timestamp with time zone DEFAULT NULL::timestamp with time zone, _notification_email text DEFAULT NULL::text, _tenant_id integer DEFAULT 1)
    returns TABLE(__api_key_id integer, __api_key text, __api_secret text)
    rows 1
    language plpgsql
as
$$
declare
	__permission_code text;
	__api_secret      text;
	__api_secret_hash bytea;
	__api_key         text;
	__last_id         int;
	__api_user_id     bigint;
	__tenant_id       int;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.create_api_key', _tenant_id);

	__tenant_id := coalesce(_tenant_id, 1);

	__api_key := coalesce(_api_key, auth.generate_api_key());
	__api_secret := coalesce(_api_secret, auth.generate_api_secret());
	__api_secret_hash := auth.generate_api_secret_hash(__api_secret);

	insert into auth.api_key( created_by, updated_by, tenant_id, title, description, api_key, secret_hash, expire_at
													, notification_email)
	values ( _created_by, _created_by, _tenant_id, _title, _description, __api_key, __api_secret_hash, _expire_at
				 , _notification_email)
	returning api_key_id
		into __last_id;

	select user_id
	from unsecure.create_api_user(_created_by, _user_id, _correlation_id, __api_key, __tenant_id)
	into __api_user_id;

	if _perm_set_code is not null and _perm_set_code <> '' then
		perform unsecure.assign_permission(_created_by, _user_id, _correlation_id, _target_user_id := __api_user_id,
																			 _perm_set_code := _perm_set_code, _tenant_id := __tenant_id);
	end if;

	if _permission_codes is not null and _permission_codes <> (array [])::text[] then
		foreach __permission_code in array _permission_codes
			loop
				perform unsecure.assign_permission(_created_by, _user_id, _correlation_id, _target_user_id := __api_user_id,
																					 _perm_code := __permission_code, _tenant_id := __tenant_id);
			end loop;
	end if;

	return query
		select __last_id, __api_key, __api_secret;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 14001  -- apikey_created
			, 'api_key', __last_id
			, jsonb_strip_nulls(jsonb_build_object('api_key_title', coalesce(_title, __api_key)
				, 'api_key', __api_key, 'description', _description
				, 'expire_at', _expire_at, 'notification_email', _notification_email
				, 'perm_set_code', _perm_set_code, 'permission_codes', _permission_codes))
			, __tenant_id);

end;
$$;

create or replace function auth.search_api_keys(_user_id bigint, _correlation_id text, _search_text text, _page integer DEFAULT 1, _page_size integer DEFAULT 10, _tenant_id integer DEFAULT 1)
    returns TABLE(__created_by text, __created_at timestamp with time zone, __updated_by text, __updated_at timestamp with time zone, __api_key_id integer, __tenant_id integer, __title text, __description text, __api_key text, __expire_at timestamp with time zone, __notification_email text, __total_items bigint)
    stable
    rows 100
    language plpgsql
as
$$
declare
	__search_text text;
begin
	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.search', _tenant_id);

	__search_text := helpers.normalize_text(_search_text);

	_page := case when _page is null then 1 else _page end;
	_page_size := case when _page_size is null then 10 else least(_page_size, 100) end;

	return query
		with filtered_rows
					 as (select ak.api_key_id
										, count(*) over () as total_items
							 from auth.api_key ak
							 where (_tenant_id is null or ak.tenant_id = _tenant_id)
								 and (helpers.is_empty_string(__search_text) or lower(ak.title) like '%' || __search_text || '%')
							 order by ak.title, ak.api_key
							 offset ((_page - 1) * _page_size) limit _page_size)
		select ak.created_by
				 , ak.created_at
				 , ak.updated_by
				 , ak.updated_at
				 , ak.api_key_id
				 , ak.tenant_id
				 , ak.title
				 , ak.description
				 , ak.api_key
				 , ak.expire_at
				 , ak.notification_email
				 , total_items
		from filtered_rows fr
					 inner join auth.api_key ak on fr.
																					 api_key_id = ak.api_key_id;
end;
$$;

create or replace function auth.get_api_key_permissions(_user_id bigint, _correlation_id text, _api_key_id integer, _tenant_id integer)
    returns TABLE(__assignment_id bigint, __perm_set_code text, __perm_set_title text, __user_group_member_id bigint, __user_group_title text, __permission_inheritance_type text, __permission_code text, __permission_title text)
    stable
    language plpgsql
as
$$
begin
	return query
		select p.*
		from auth.api_key ak
					 inner join auth.user_info ui on user_type_code = 'api' and code = auth.generate_api_key_username(ak.api_key)
			 , lateral (select * from auth.get_user_permissions(_user_id, _correlation_id, ui.user_id)) as p
		where ak.api_key_id = _api_key_id
			and tenant_id = _tenant_id;
end;
$$;

create or replace function auth.update_api_key(_updated_by text, _user_id bigint, _correlation_id text, _api_key_id integer, _title text, _description text, _expire_at timestamp with time zone, _notification_email text, _tenant_id integer DEFAULT 1)
    returns TABLE(__api_key_id integer, __title text, __description text, __expire_at timestamp with time zone, __notification_email text)
    rows 1
    language plpgsql
as
$$
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_api_key', _tenant_id);

	update auth.api_key
	set updated_by         = _updated_by
		, updated_at         = now()
		, title              = _title
		, description        = _description
		, expire_at          = _expire_at
		, notification_email = _notification_email
	where api_key_id = _api_key_id
		and tenant_id = _tenant_id;

	return query
		select api_key_id, title, description, expire_at, notification_email
		from auth.api_key
		where api_key_id = _api_key_id
			and tenant_id = _tenant_id;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 14002  -- apikey_updated
			, 'api_key', _api_key_id
			, jsonb_build_object('api_key_title', _title, 'description', _description
				, 'expire_at', _expire_at, 'notification_email', _notification_email)
			, _tenant_id);
end;
$$;

create or replace function auth.assign_api_key_permissions(_created_by text, _user_id bigint, _correlation_id text, _api_key_id integer, _perm_set_code text, _permission_codes text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__assignment_id bigint, __tenant_id integer, __perm_set_id integer, __perm_set_code text, __perm_set_title text, __permission_full_code text, __permission_full_title text, __permission_title text)
    rows 1
    language plpgsql
as
$$
declare
	__permission_code text;
	__api_user_id     bigint;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_permissions', _tenant_id);

	select user_id
	from auth.api_key ak
				 inner join auth.user_info ui on ui.code = auth.generate_api_key_username(ak.api_key)
	where api_key_id = _api_key_id
	into __api_user_id;

	if _perm_set_code is not null then
		perform unsecure.assign_permission(_created_by, _user_id, _correlation_id, _target_user_id := __api_user_id,
																			 _perm_set_code := _perm_set_code,
																			 _tenant_id := _tenant_id);
	end if;

	if _permission_codes is not null then
		foreach __permission_code in array _permission_codes
			loop
				perform unsecure.assign_permission(_created_by, _user_id, _correlation_id, _target_user_id := __api_user_id,
																					 _perm_code := __permission_code,
																					 _tenant_id := _tenant_id);
			end loop;
	end if;

	return query
		select pa.assignment_id
				 , pa.tenant_id
				 , pa.perm_set_id
				 , ps.code
				 , ps.title
				 , p.full_code::text
				 , p.full_title
				 , p.title
		from auth.permission_assignment pa
					 left join auth.perm_set ps on pa.perm_set_id = ps.perm_set_id
					 left join auth.permission p on pa.permission_id = p.permission_id
		where pa.user_id = __api_user_id
		order by ps.code nulls last, p.full_code;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 14002  -- apikey_updated (permissions assigned)
			, 'api_key', _api_key_id
			, jsonb_build_object('api_key_title', _api_key_id::text
				, 'action', 'permissions_assigned', 'perm_set_code', _perm_set_code
				, 'permission_codes', array_to_string(_permission_codes, ';'))
			, _tenant_id);
end;
$$;

create or replace function auth.unassign_api_key_permissions(_deleted_by text, _user_id bigint, _correlation_id text, _api_key_id integer, _perm_set_code text, _permission_codes text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__assignment_id bigint, __perm_set_id integer, __perm_set_code text, __perm_set_title text, __permission_full_code text, __permission_full_title text, __permission_title text)
    rows 1
    language plpgsql
as
$$
declare
	__permission_code text;
	__assignment_id   bigint;
	__null_bigint     bigint;
	__api_user_id     bigint;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_permissions', _tenant_id);

	select user_id
	from auth.api_key ak
				 inner join auth.user_info ui on ui.code = auth.generate_api_key_username(ak.api_key)
	where api_key_id = _api_key_id
	into __api_user_id;

	if _perm_set_code is not null then
		select up.assignment_id
		from auth.perm_set ps
					 inner join auth.permission_assignment pa
											on pa.user_id = __api_user_id and ps.perm_set_id = pa.perm_set_id and
												 pa.tenant_id = _tenant_id
			 , lateral unsecure.unassign_permission(_deleted_by, _user_id, _correlation_id, pa.assignment_id, _tenant_id) as up
		where ps.code = _perm_set_code
		into __null_bigint;
	end if;

	if _permission_codes is not null then
		foreach __permission_code in array _permission_codes
			loop
				for __assignment_id in
					select pa.assignment_id
					from auth.permission p
								 inner join auth.permission_assignment pa
														on pa.user_id = __api_user_id and p.permission_id = pa.permission_id and
															 pa.tenant_id = _tenant_id
					where p.full_code = __permission_code::ext.ltree
					loop
						perform unsecure.unassign_permission(_deleted_by, _user_id, _correlation_id, __assignment_id, _tenant_id);
					end loop;
			end loop;
	end if;

	return query
		select pa.assignment_id, pa.perm_set_id, ps.code, ps.title, p.full_code::text, p.full_title, p.title
		from auth.permission_assignment pa
					 inner join auth.perm_set ps on pa.perm_set_id = ps.perm_set_id
					 inner join auth.permission p on pa.permission_id = p.permission_id
		where pa.user_id = __api_user_id
		order by ps.code nulls last, p.full_code;

	perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 14002  -- apikey_updated (permissions unassigned)
			, 'api_key', _api_key_id
			, jsonb_build_object('api_key_title', _api_key_id::text
				, 'action', 'permissions_unassigned', 'perm_set_code', _perm_set_code
				, 'permission_codes', array_to_string(_permission_codes, ';'))
			, _tenant_id);

end;
$$;

create or replace function auth.delete_api_key(_deleted_by text, _user_id bigint, _correlation_id text, _api_key_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__api_key_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__api_user_id bigint;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.delete_api_key', _tenant_id);

	select user_id
	from auth.api_key ak
				 inner join auth.user_info ui on ui.code = auth.generate_api_key_username(ak.api_key)
	where api_key_id = _api_key_id
	into __api_user_id;

	delete from auth.permission_assignment where user_id = __api_user_id;

	perform unsecure.delete_user_by_id(_deleted_by, _user_id, _correlation_id, __api_user_id) du;

	return query
		delete from auth.api_key where api_key_id = _api_key_id
			returning api_key_id;

	perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 14003  -- apikey_deleted
			, 'api_key', _api_key_id
			, jsonb_build_object('api_key_title', _api_key_id::text)
			, _tenant_id);

end;
$$;

create or replace function auth.update_api_key_secret(_updated_by text, _user_id bigint, _correlation_id text, _api_key_id integer, _api_secret text DEFAULT NULL::text, _tenant_id integer DEFAULT 1)
    returns TABLE(__api_key_id integer, __api_secret text)
    rows 1
    language plpgsql
as
$$
declare
	__api_secret      text;
	__api_secret_hash bytea;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_api_secret', _tenant_id);

	__api_secret := coalesce(_api_secret, auth.generate_api_secret());
	__api_secret_hash := auth.generate_api_secret_hash(__api_secret);

	update auth.api_key
	set updated_by  = _updated_by
		, updated_at  = now()
		, secret_hash = __api_secret_hash
	where api_key_id = _api_key_id
		and tenant_id = _tenant_id;

	return query
		select _api_key_id, __api_secret;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 14002  -- apikey_updated (secret rotated)
			, 'api_key', _api_key_id
			, jsonb_build_object('api_key_title', _api_key_id::text, 'action', 'secret_rotated')
			, _tenant_id);

end;
$$;

create or replace function auth.validate_api_key(_requested_by text, _user_id bigint, _correlation_id text, _api_key text, _api_secret text, _request_context jsonb DEFAULT NULL::jsonb, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_id bigint, __username text, __user_display_name text, __permission_full_codes text[])
    rows 1
    language plpgsql
as
$$
declare
	__api_user_id bigint;
begin

	perform auth.has_permission(_user_id, _correlation_id, 'api_keys.validate_api_key', _tenant_id);

	select user_id
	from auth.api_key ak
				 inner join auth.user_info ui on ui.code = auth.generate_api_key_username(ak.api_key)
	where ak.api_key = _api_key
		and ak.secret_hash = auth.generate_api_secret_hash(_api_secret)
		and ak.tenant_id = _tenant_id
	into __api_user_id;

	if __api_user_id is null then

		perform auth.create_user_event(_requested_by, _user_id, _correlation_id,
			'api_key_validating', __api_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('is_successful', false));

		perform error.raise_52301(_api_key);
	end if;

	return query
		with pa as (select u.display_name, u.username, pa.perm_set_id, pa.permission_id
								from auth.permission_assignment pa
											 inner join auth.user_info u on u.user_id = pa.user_id
								where pa.user_id = __api_user_id
									and pa.tenant_id = _tenant_id)
			 , permissions as (select ep.permission_code::text
												 from pa
																inner join auth.effective_permissions ep on pa.perm_set_id = ep.perm_set_id
												 union
												 distinct
												 select p.full_code::text
												 from pa
																inner join auth.permission p on pa.permission_id = p.permission_id)
		select ui.user_id, ui.username, ui.display_name, array_agg(permission_code)
		from auth.user_info ui
					 left join permissions p on true
		where ui.user_id = __api_user_id
		group by ui.user_id, ui.username, ui.display_name;

	perform auth.create_user_event(_requested_by, _user_id, _correlation_id,
		'api_key_validating', __api_user_id,
		_request_context := _request_context,
		_event_data := jsonb_build_object('is_successful', true));

end;
$$;

-- ============================================================================
-- Outbound API Key Functions
-- ============================================================================
-- For storing credentials to call external services (SendGrid, Slack, Azure, etc.)
-- Encryption/decryption is handled by the application layer; PostgreSQL stores
-- pre-encrypted bytea data.

create or replace function auth.create_outbound_api_key(
    _created_by text,
    _user_id bigint,
    _correlation_id text,
    _title text,
    _description text,
    _service_code text,
    _encrypted_secret bytea,
    _service_url text DEFAULT NULL,
    _extra_data jsonb DEFAULT NULL,
    _expire_at timestamp with time zone DEFAULT NULL,
    _notification_email text DEFAULT NULL,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(__api_key_id integer, __api_key text, __service_code text)
    rows 1
    language plpgsql
as
$$
declare
    __api_key text;
    __last_id int;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.create_api_key', _tenant_id);

    if _service_code is null or _service_code = '' then
        raise exception 'Service code is required for outbound API keys'
            using errcode = '22023';
    end if;

    if _encrypted_secret is null then
        raise exception 'Encrypted secret is required for outbound API keys'
            using errcode = '22023';
    end if;

    __api_key := 'outbound_' || _service_code || '_' || auth.generate_api_key();

    insert into auth.api_key(
        created_by, updated_by, tenant_id, title, description,
        api_key, key_type, encrypted_secret, service_code, service_url,
        extra_data, expire_at, notification_email
    )
    values (
        _created_by, _created_by, _tenant_id, _title, _description,
        __api_key, 'outbound', _encrypted_secret, lower(_service_code), _service_url,
        _extra_data, _expire_at, _notification_email
    )
    returning api_key_id into __last_id;

    return query
        select __last_id, __api_key, lower(_service_code);

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 14001  -- apikey_created
        , 'api_key', __last_id
        , jsonb_strip_nulls(jsonb_build_object(
            'api_key_title', coalesce(_title, __api_key),
            'key_type', 'outbound',
            'service_code', _service_code,
            'service_url', _service_url,
            'expire_at', _expire_at,
            'notification_email', _notification_email))
        , _tenant_id);
end;
$$;

create or replace function auth.get_outbound_api_key(
    _user_id bigint,
    _correlation_id text,
    _service_code text,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __api_key text,
        __title text,
        __description text,
        __service_code text,
        __service_url text,
        __extra_data jsonb,
        __expire_at timestamp with time zone,
        __notification_email text,
        __created_at timestamp with time zone,
        __updated_at timestamp with time zone
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.search', _tenant_id);

    return query
        select ak.api_key_id, ak.api_key, ak.title, ak.description,
               ak.service_code, ak.service_url, ak.extra_data,
               ak.expire_at, ak.notification_email,
               ak.created_at, ak.updated_at
        from auth.api_key ak
        where ak.tenant_id = _tenant_id
          and ak.key_type = 'outbound'
          and ak.service_code = lower(_service_code);
end;
$$;

create or replace function auth.get_outbound_api_key_by_id(
    _user_id bigint,
    _correlation_id text,
    _api_key_id integer,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __api_key text,
        __title text,
        __description text,
        __service_code text,
        __service_url text,
        __extra_data jsonb,
        __expire_at timestamp with time zone,
        __notification_email text,
        __created_at timestamp with time zone,
        __updated_at timestamp with time zone
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.search', _tenant_id);

    return query
        select ak.api_key_id, ak.api_key, ak.title, ak.description,
               ak.service_code, ak.service_url, ak.extra_data,
               ak.expire_at, ak.notification_email,
               ak.created_at, ak.updated_at
        from auth.api_key ak
        where ak.tenant_id = _tenant_id
          and ak.key_type = 'outbound'
          and ak.api_key_id = _api_key_id;
end;
$$;

-- Retrieves encrypted secret for outbound API keys.
-- Requires api_keys.read_outbound_secret permission.
-- Decryption is handled by application layer.
create or replace function auth.get_outbound_api_key_secret(
    _requested_by text,
    _user_id bigint,
    _correlation_id text,
    _service_code text,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __service_code text,
        __service_url text,
        __encrypted_secret bytea,
        __extra_data jsonb
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.read_outbound_secret', _tenant_id);

    return query
        select ak.api_key_id, ak.service_code, ak.service_url,
               ak.encrypted_secret, ak.extra_data
        from auth.api_key ak
        where ak.tenant_id = _tenant_id
          and ak.key_type = 'outbound'
          and ak.service_code = lower(_service_code)
          and (ak.expire_at is null or ak.expire_at > now());

    -- Read operation - journal message omitted for performance
    -- Use audit events for security-sensitive access tracking if needed
end;
$$;

create or replace function auth.get_outbound_api_key_secret_by_id(
    _requested_by text,
    _user_id bigint,
    _correlation_id text,
    _api_key_id integer,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __service_code text,
        __service_url text,
        __encrypted_secret bytea,
        __extra_data jsonb
    )
    stable
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.read_outbound_secret', _tenant_id);

    return query
        select ak.api_key_id, ak.service_code, ak.service_url,
               ak.encrypted_secret, ak.extra_data
        from auth.api_key ak
        where ak.tenant_id = _tenant_id
          and ak.key_type = 'outbound'
          and ak.api_key_id = _api_key_id
          and (ak.expire_at is null or ak.expire_at > now());
end;
$$;

create or replace function auth.update_outbound_api_key(
    _updated_by text,
    _user_id bigint,
    _correlation_id text,
    _api_key_id integer,
    _title text,
    _description text,
    _service_url text DEFAULT NULL,
    _extra_data jsonb DEFAULT NULL,
    _expire_at timestamp with time zone DEFAULT NULL,
    _notification_email text DEFAULT NULL,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __title text,
        __description text,
        __service_url text,
        __extra_data jsonb,
        __expire_at timestamp with time zone,
        __notification_email text
    )
    rows 1
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_api_key', _tenant_id);

    update auth.api_key
    set updated_by = _updated_by,
        updated_at = now(),
        title = _title,
        description = _description,
        service_url = _service_url,
        extra_data = _extra_data,
        expire_at = _expire_at,
        notification_email = _notification_email
    where api_key_id = _api_key_id
      and tenant_id = _tenant_id
      and key_type = 'outbound';

    return query
        select ak.api_key_id, ak.title, ak.description, ak.service_url,
               ak.extra_data, ak.expire_at, ak.notification_email
        from auth.api_key ak
        where ak.api_key_id = _api_key_id
          and ak.tenant_id = _tenant_id;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 14002  -- apikey_updated
        , 'api_key', _api_key_id
        , jsonb_build_object('api_key_title', _title, 'key_type', 'outbound',
            'description', _description, 'service_url', _service_url,
            'expire_at', _expire_at, 'notification_email', _notification_email)
        , _tenant_id);
end;
$$;

-- Update encrypted secret for outbound API key.
-- Application encrypts new secret before calling this function.
create or replace function auth.update_outbound_api_key_secret(
    _updated_by text,
    _user_id bigint,
    _correlation_id text,
    _api_key_id integer,
    _encrypted_secret bytea,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(__api_key_id integer, __service_code text)
    rows 1
    language plpgsql
as
$$
declare
    __service_code text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.update_api_secret', _tenant_id);

    if _encrypted_secret is null then
        raise exception 'Encrypted secret is required'
            using errcode = '22023';
    end if;

    update auth.api_key
    set updated_by = _updated_by,
        updated_at = now(),
        encrypted_secret = _encrypted_secret
    where api_key_id = _api_key_id
      and tenant_id = _tenant_id
      and key_type = 'outbound'
    returning service_code into __service_code;

    if __service_code is null then
        raise exception 'Outbound API key not found'
            using errcode = '02000';
    end if;

    return query
        select _api_key_id, __service_code;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 14002  -- apikey_updated (secret rotated)
        , 'api_key', _api_key_id
        , jsonb_build_object('api_key_id', _api_key_id, 'key_type', 'outbound',
            'action', 'secret_rotated', 'service_code', __service_code)
        , _tenant_id);
end;
$$;

create or replace function auth.search_outbound_api_keys(
    _user_id bigint,
    _correlation_id text,
    _search_text text DEFAULT NULL,
    _service_code text DEFAULT NULL,
    _page integer DEFAULT 1,
    _page_size integer DEFAULT 10,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(
        __api_key_id integer,
        __api_key text,
        __title text,
        __description text,
        __service_code text,
        __service_url text,
        __extra_data jsonb,
        __expire_at timestamp with time zone,
        __notification_email text,
        __created_at timestamp with time zone,
        __updated_at timestamp with time zone,
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
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.search', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 10), 100);

    return query
        with filtered_rows as (
            select ak.api_key_id, count(*) over () as total_items
            from auth.api_key ak
            where ak.tenant_id = _tenant_id
              and ak.key_type = 'outbound'
              and (_service_code is null or ak.service_code = lower(_service_code))
              and (helpers.is_empty_string(__search_text)
                   or lower(ak.title) like '%' || __search_text || '%'
                   or lower(ak.service_code) like '%' || __search_text || '%')
            order by ak.service_code, ak.title
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select ak.api_key_id, ak.api_key, ak.title, ak.description,
               ak.service_code, ak.service_url, ak.extra_data,
               ak.expire_at, ak.notification_email,
               ak.created_at, ak.updated_at, fr.total_items
        from filtered_rows fr
        inner join auth.api_key ak on fr.api_key_id = ak.api_key_id;
end;
$$;

create or replace function auth.delete_outbound_api_key(
    _deleted_by text,
    _user_id bigint,
    _correlation_id text,
    _api_key_id integer,
    _tenant_id integer DEFAULT 1
)
    returns TABLE(__api_key_id integer, __service_code text)
    rows 1
    language plpgsql
as
$$
declare
    __service_code text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'api_keys.delete_api_key', _tenant_id);

    delete from auth.api_key
    where api_key_id = _api_key_id
      and tenant_id = _tenant_id
      and key_type = 'outbound'
    returning service_code into __service_code;

    if __service_code is null then
        raise exception 'Outbound API key not found'
            using errcode = '02000';
    end if;

    return query
        select _api_key_id, __service_code;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
        , 14003  -- apikey_deleted
        , 'api_key', _api_key_id
        , jsonb_build_object('api_key_id', _api_key_id, 'key_type', 'outbound',
            'service_code', __service_code)
        , _tenant_id);
end;
$$;

