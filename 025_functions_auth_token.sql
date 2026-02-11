/*
 * Auth Token Functions
 * ====================
 *
 * Token management: create, validate, set as used/failed
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.create_token(_created_by text, _user_id bigint, _target_user_id bigint, _target_user_oid text, _user_event_id integer, _token_type_code text, _token_channel_code text, _token text, _expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, _token_data jsonb DEFAULT NULL::jsonb)
    returns TABLE(___token_id bigint, ___token_uid text, ___expires_at timestamp with time zone)
    language plpgsql
as
$$
declare
	__default_expiration_in_seconds int;
-- 	__last_id                       bigint;
-- 	__token_uid                     text;
-- 	__token_expires_at              timestamptz;
	__last_item                     auth.token;
	__target_username               text;
begin
	perform
		auth.has_permission(_user_id, 'tokens.create_token');

	if
		_expires_at is null then

		select default_expiration_in_seconds
		from const.token_type
		where code = _token_type_code
		into __default_expiration_in_seconds;

		_expires_at := now() + '1 second'::interval * __default_expiration_in_seconds;
	end if;

	if
		_target_user_id is not null then
		-- invalidate all previous tokens of the same type for the same user that are still valid
		update auth.token
		set updated_at       = now()
			, updated_by       = _created_by
			, token_state_code = 'invalid'
		where user_id = _target_user_id
			and token_type_code = _token_type_code
			and token_state_code = 'valid';
	end if;

	if
		exists(select
					 from auth.token
					 where token = _token
						 and token_state_code = 'valid'
						 and token_type_code = _token_type_code) then
		perform error.raise_52276();
	end if;

	insert into auth.token ( created_by, user_id, user_oid, user_event_id, token_type_code, token_channel_code, token
												 , expires_at, token_data)
	values ( _created_by
				 , _target_user_id
				 , _target_user_oid
				 , _user_event_id
				 , _token_type_code
				 , _token_channel_code
				 , _token
				 , _expires_at
				 , _token_data)
	returning *
		into __last_item;

	select username
	from auth.user_info ui
	where ui.user_id = __last_item.user_id
	into __target_username;

	perform
		add_journal_msg_jsonb(_created_by, _user_id
			, format('Token: (type: %s, uid: %s) for user: (upn: %s) created by: %s'
														, __last_item.token_type_code, __last_item.uid, __target_username, _created_by)
			, 'token', __last_item.token_id
			, jsonb_build_object('user_id', __last_item.user_id, 'username', __target_username)
			, 50401
			, _tenant_id := 1);

	return query
		select __last_item.token_id, __last_item.uid, __last_item.expires_at;

	perform unsecure.expire_tokens(_created_by);
end;
$$;

create or replace function auth.set_token_as_used(_updated_by text, _user_id bigint, _token_uid text, _token text, _token_type_code text, _ip_address text, _user_agent text, _origin text)
    returns TABLE(__token_id bigint, __token_uid text, __token_state_code text, __used_at timestamp with time zone, __user_id bigint, __user_oid text, __token_data jsonb)
    language plpgsql
as
$$
declare
	__last_item       auth.token;
	__target_username text;
begin

	perform
		auth.has_permission(_user_id, 'tokens.set_as_used');

	select *
	from auth.token
	where (helpers.is_not_empty_string(_token_uid) or helpers.is_not_empty_string(_token))
		and uid = _token_uid
		and token = _token
		and token_type_code = _token_type_code
		and token_state_code = 'valid'
	into __last_item;

	select username
	from auth.user_info ui
	where ui.user_id = __last_item.user_id
	into __target_username;

	return query
		update auth.token
			set updated_by = _updated_by, updated_at = now(), token_state_code = 'used', used_at = now(), ip_address = _ip_address, user_agent = _user_agent, origin = _origin
			where
				(helpers.is_empty_string(_token_uid) or _token_uid = uid)
					and token = _token
			returning token_id
				, uid
				, token_state_code
				, used_at
				, user_id
				, user_oid
				, token_data;

	perform
		add_journal_msg_jsonb(_updated_by, _user_id
			, format('Token: (type: %s, uid: %s) for user: (upn: %s) set as used'
														, __last_item.token_type_code, __last_item.uid, __target_username)
			, 'token', __last_item.token_id
			, jsonb_build_object('user_id', __last_item.user_id, 'username', __target_username
														, 'ip_address', _ip_address
														, 'user_agent', _user_agent
														, 'origin', _origin)
			, _event_id := 50403
			, _tenant_id := 1);
end;
$$;

create or replace function auth.set_token_as_used_by_token(_updated_by text, _user_id bigint, _token text, _token_type text, _ip_address text, _user_agent text, _origin text)
    returns TABLE(__token_id bigint, __token_uid text, __token_state_code text, __used_at timestamp with time zone, __user_id bigint, __user_oid text, __token_data jsonb)
    language plpgsql
as
$$
declare
	__token_uid text;
begin

	select uid
	from auth.token
	where token_type_code = _token_type
		and token = _token
	into __token_uid;

	return query
		select *
		from auth.set_token_as_used(_updated_by,
																_user_id,
																__token_uid,
																_token,
																_token_type,
																_ip_address,
																_user_agent,
																_origin
				 );
end;
$$;

create or replace function auth.set_token_as_failed(_updated_by text, _user_id bigint, _token_uid text, _token text, _token_type_code text, _ip_address text, _user_agent text, _origin text)
    returns TABLE(__token_id bigint, __token_uid text, __token_state_code text, __used_at timestamp with time zone, __user_id bigint, __user_oid text, __token_data jsonb)
    language plpgsql
as
$$
declare
	__token_id  bigint;
	__token_uid text;
begin

	perform
		auth.has_permission(_user_id, 'tokens.set_as_used');

	select token_id, uid
	from auth.token
	where (helpers.is_not_empty_string(_token_uid) or helpers.is_not_empty_string(_token))
		and uid = _token_uid
		and token = _token
		and token_type_code = _token_type_code
		and token_state_code = 'valid'
	into __token_id, __token_uid;


	-- 	if helpers.is_empty_string(__token_uid) then
-- 		perform error.raise_52278(__token_uid);
-- 	end if;

	return query
		update auth.token
			set updated_by = _updated_by, updated_at = now(), token_state_code = 'validation_failed', used_at = now(), ip_address = _ip_address, user_agent = _user_agent, origin = _origin
			where
					(helpers.is_empty_string(_token_uid) or _token_uid = uid)
					and token = _token
			returning token_id
				, uid
				, token_state_code
				, used_at
				, user_id
				, user_oid
				, token_data;

	perform
		add_journal_msg(_updated_by, _user_id
			, format('Token (uid: %s) set as validation_failed by user: %s'
											, _token_uid, _updated_by)
			, 'token', __token_id
			, array ['ip_address', _ip_address, 'user_agent', _user_agent, 'origin', _origin]
			, _event_id := 50403
			, _tenant_id := 1);

end;
$$;

create or replace function auth.set_token_as_failed_by_token(_updated_by text, _user_id bigint, _token text, _token_type text, _ip_address text, _user_agent text, _origin text)
    returns TABLE(__token_id bigint, __token_uid text, __token_state_code text, __used_at timestamp with time zone, __user_id bigint, __user_oid text, __token_data jsonb)
    language plpgsql
as
$$
declare
	__token_uid text;
begin

	select uid
	from auth.token
	where token_type_code = _token_type
		and token = _token
	into __token_uid;

	return query
		select *
		from auth.set_token_as_failed(_updated_by,
																	_user_id,
																	__token_uid,
																	_token,
																	_token_type,
																	_ip_address,
																	_user_agent,
																	_origin
				 );
end;
$$;

create or replace function auth.validate_token(_updated_by text, _user_id bigint, _target_user_id bigint, _token_uid text, _token text, _token_type_code text, _ip_address text, _user_agent text, _origin text, _set_as_used boolean DEFAULT false)
    returns TABLE(___token_id bigint, ___token_uid text, ___token_state_code text, ___used_at timestamp with time zone, ___user_id bigint, ___user_oid text, ___token_data jsonb)
    language plpgsql
as
$$
declare
	__target_username text;
	__last_item       auth.token;
begin
	perform
		auth.has_permission(_user_id, 'tokens.validate_token');

	select *
	from auth.token
	where ((_target_user_id is not null and token.user_id = _target_user_id) or true)
		and token_type_code = _token_type_code
		and (helpers.is_not_empty_string(_token_uid) or helpers.is_not_empty_string(_token))
		and (helpers.is_empty_string(_token_uid) or uid = _token_uid)
		and (helpers.is_empty_string(_token) or token = _token)
	into __last_item;

	if
		__last_item.token_id is null then
		perform error.raise_52277();
	end if;

	if
		__last_item.token_state_code <> 'valid' then
		perform error.raise_52278(__last_item.uid);
	end if;

	if
		_target_user_id is not null and _target_user_id <> __last_item.user_id then
		perform error.raise_52279(__last_item.uid);
	end if;

	select username
	from auth.user_info ui
	where ui.user_id = __last_item.user_id
	into __target_username;

	perform
		add_journal_msg_jsonb(_updated_by, _user_id
			, format('Token: (type: %s, uid: %s) for user: (upn: %s) validated by: %s'
														, __last_item.token_type_code, __last_item.uid, __target_username, _updated_by)
			, 'token', __last_item.token_id
			, jsonb_build_object('user_id', __last_item.user_id, 'username', __target_username
														, 'ip_address', _ip_address
														, 'user_agent', _user_agent
														, 'origin', _origin)
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
			from auth.set_token_as_used(_updated_by, _user_id, __last_item.uid, _token,
																	_token_type_code, _ip_address, _user_agent,
																	_origin) used_token;
	else
		return query
			select __last_item.token_id,
						 __last_item.uid,
						 __last_item.token_state_code,
						 __last_item.used_at,
						 __last_item.user_id,
						 __last_item.user_oid,
						 __last_item.token_data;
	end if;

	-- invalidate old tokens, this way we don't need a job to do that, every user will work for us this way
	perform unsecure.expire_tokens(_updated_by);
end;
$$;

