/*
 * Auth User Functions
 * ===================
 *
 * User management: registration, identity, preferences, enable/disable/lock
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.enable_user(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint,
    _request_context jsonb default null)
    returns TABLE(__user_id bigint, __is_active boolean, __is_locked boolean)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.enable_user');

	return query
		update auth.user_info
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = true
			where is_system = false
				and user_id = _target_user_id
			returning user_id
				, is_active
				, is_locked;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10004  -- user_enabled
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'user_enabled', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.disable_user(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint,
    _request_context jsonb default null)
    returns TABLE(__user_id bigint, __is_active boolean, __is_locked boolean)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.disable_user');

	return query
		update auth.user_info
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = false
			where is_system = false
				and user_id = _target_user_id
			returning user_id
				, is_active
				, is_locked;

	-- Clear permission cache for all tenants to ensure immediate effect
	perform unsecure.clear_permission_cache(_updated_by, _target_user_id, null);

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10005  -- user_disabled
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'user_disabled', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.unlock_user(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint,
    _request_context jsonb default null)
    returns TABLE(__user_id bigint, __is_active boolean, __is_locked boolean)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.unlock_user');

	return query
		update auth.user_info
			set updated_by = _updated_by
				, updated_at = now()
				, is_locked = false
			where is_system = false
				and user_id = _target_user_id
			returning user_id
				, is_active
				, is_locked;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10007  -- user_unlocked
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'user_unlocked', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.lock_user(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint,
    _request_context jsonb default null)
    returns TABLE(__user_id bigint, __is_active boolean, __is_locked boolean)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.lock_user');

	return query
		update auth.user_info
			set updated_by = _updated_by
				, updated_at = now()
				, is_locked = true
			where is_system = false
				and user_id = _target_user_id
			returning user_id
				, is_active
				, is_locked;

	-- Clear permission cache for all tenants to ensure immediate effect
	perform unsecure.clear_permission_cache(_updated_by, _target_user_id, null);

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10006  -- user_locked
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'user_locked', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.enable_user_identity(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text,
    _request_context jsonb default null)
    returns TABLE(__user_identity_id bigint, __is_active boolean)
    rows 1
    language plpgsql
as
$$
declare
	__user_identity_id bigint;
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.enable_user_identity');

	select user_identity_id
	from auth.user_identity uid
				 inner join auth.user_info ui on uid.user_id = ui.user_id
	where not ui.is_system
		and uid.user_id = _target_user_id
		and provider_code = _provider_code
	into __user_identity_id;

	if
		__user_identity_id is null then
		perform error.raise_52111(_target_user_id, _provider_code);
	end if;

	return query
		update auth.user_identity
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = true
			where user_identity_id = __user_identity_id
			returning user_identity_id
				, is_active;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10033  -- identity_enabled
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text, 'provider_code', _provider_code)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'identity_enabled', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.disable_user_identity(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text,
    _request_context jsonb default null)
    returns TABLE(__user_identity_id bigint, __is_active boolean)
    rows 1
    language plpgsql
as
$$
declare
	__user_identity_id bigint;
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.disable_user_identity');

	select user_identity_id
	from auth.user_identity uid
				 inner join auth.user_info ui on uid.user_id = ui.user_id
	where not ui.is_system
		and uid.user_id = _target_user_id
		and provider_code = _provider_code
	into __user_identity_id;

	if
		__user_identity_id is null then
		perform error.raise_52111(_target_user_id, _provider_code);
	end if;

	return query
		update auth.user_identity
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = false
			where user_identity_id = __user_identity_id
			returning user_identity_id
				, is_active;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10034  -- identity_disabled
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text, 'provider_code', _provider_code)
			, 1
			, _request_context);

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
		'identity_disabled', _target_user_id, _request_context := _request_context);
end;
$$;

create or replace function auth.create_service_user_info(_created_by text, _user_id bigint, _correlation_id text, _username text, _email text DEFAULT NULL::text, _display_name text DEFAULT NULL::text, _custom_service_user_id bigint DEFAULT NULL::bigint)
    returns TABLE(__user_id bigint, __username text, __email text, __display_name text)
    rows 1
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, _correlation_id, 'users.create_service_user');

	return query
		select user_id, username, email, display_name
		from unsecure.create_service_user_info(_created_by, _user_id, _correlation_id, _username,
																					 _email, _display_name,
																					 _custom_service_user_id);
end;
$$;

create or replace function auth.update_user_password(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _password_hash text, _request_context jsonb, _password_salt text DEFAULT NULL::text)
    returns TABLE(__user_id bigint, __provider_code text, __provider_uid text)
    rows 1
    language plpgsql
as
$$
begin

	if
		_user_id <> _target_user_id then
		perform auth.has_permission(_user_id, _correlation_id, 'users.change_password');
	end if;

	perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id, 'change_password',
		_target_user_id, _request_context := _request_context);

	return query
		select *
		from unsecure.update_user_password(_updated_by, _user_id, _correlation_id, _target_user_id,
																			 _password_hash,
																			 _password_salt);
end;
$$;

create or replace function auth.register_user(_created_by text, _user_id bigint, _correlation_id text, _email text, _password_hash text, _display_name text, _user_data jsonb DEFAULT NULL::jsonb, _request_context jsonb DEFAULT NULL::jsonb)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text)
    rows 1
    language plpgsql
as
$$
declare
	__normalized_email text;
	__new_user         auth.user_info;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'users.register_user');

	__normalized_email := lower(trim(_email));

	perform
		auth.validate_provider_is_active('email');

	if
		exists(
						select
						from auth.user_identity ui
						where ui.provider_code = 'email'
							and ui.uid = __normalized_email
			) then
		perform error.raise_52102(__normalized_email);
	end if;

	select *
	from unsecure.create_user_info(_created_by, _user_id, _correlation_id, _email, _email, _display_name,
																 'email')
	into __new_user;

	perform unsecure.create_user_identity(_created_by, _user_id, _correlation_id, __new_user.user_id
		, 'email', lower(trim(_email)), lower(trim(_email)), _password_hash, _is_active := true);

	perform
		auth.update_user_data(_created_by, _user_id, _correlation_id, __new_user.user_id, 'email', _user_data);

	perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_registered',
		__new_user.user_id,
		_request_context := _request_context,
		_event_data := jsonb_build_object('email', lower(trim(_email)), 'provider', 'email'));

	return query
		select __new_user.user_id
				 , __new_user.code
				 , __new_user.uuid::text
				 , __new_user.username
				 , __new_user.email
				 , __new_user.display_name;
--      from __new_user;
end;
$$;

create or replace function auth.add_user_to_default_groups(_created_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_id bigint, __user_group_id integer, __user_group_code text, __user_group_title text)
    language plpgsql
as
$$
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'users.add_to_default_groups', _tenant_id);

	return query
		select *
		from unsecure.add_user_to_default_groups(_created_by, _user_id, _correlation_id, _target_user_id,
																						 _tenant_id);
end;
$$;

create or replace function auth.get_user_by_id(_user_id bigint, _correlation_id text)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text)
    language plpgsql
as
$$
begin
	if
		not exists(select
							 from auth.user_info ui
							 where user_id = _user_id
			) then
		perform error.raise_52103(_user_id);
	end if;

	return query
		select user_id
				 , code
				 , uuid::text
				 , username
				 , email
				 , display_name
		from auth.user_info ui
		where user_id = _user_id;
end;

$$;

create or replace function auth.get_user_identity(_user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text)
    returns TABLE(__user_identity_id bigint, __provider_code text, __uid text, __user_id bigint, __provider_groups text[], __provider_roles text[], __user_data jsonb)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.get_user_identity');

	return query
		select uid.user_identity_id
				 , uid.provider_code
				 , uid.uid
				 , uid.uid
				 , uid.user_id
				 , uid.provider_groups
				 , uid.provider_roles
				 , uid.user_data
		from auth.user_identity uid
		where user_id = _target_user_id
			and provider_code = _provider_code;
end;
$$;

create or replace function auth.get_user_identity_by_email(_user_id bigint, _correlation_id text, _email text, _provider_code text)
    returns TABLE(__user_identity_id bigint, __provider_code text, __uid text, __user_id bigint, __provider_groups text[], __provider_roles text[], __user_data jsonb)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'users.get_user_identity');

	return query
		select uid.user_identity_id
				 , uid.provider_code
				 , uid.uid
				 , uid.user_id
				 , uid.provider_groups
				 , uid.provider_roles
				 , uid.user_data
		from auth.user_info ui
					 inner join auth.user_identity uid on ui.user_id = uid.user_id
		where ui.email = _email
			and uid.provider_code = _provider_code;
end;
$$;

create or replace function auth.get_user_by_email_for_authentication(_user_id bigint, _correlation_id text, _email text, _request_context jsonb DEFAULT NULL::jsonb)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text, __provider text, __password_hash text, __password_salt text)
    language plpgsql
as
$$
declare
	__target_user_id     bigint;
	__target_uid_id      bigint;
	__normalized_email   text;
	__is_active          bool;
	__is_locked          bool;
	__is_identity_active bool;
	__can_login          bool;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'authentication.get_data');

	perform
		auth.validate_provider_is_active('email');

	__normalized_email := lower(trim(_email));

	select ui.user_id, uid.user_identity_id, ui.is_active, ui.is_locked, uid.is_active, ui.can_login
	from auth.user_identity uid
				 inner join auth.user_info ui on uid.user_id = ui.user_id
	where uid.provider_code = 'email'
		and uid.uid = __normalized_email
	into __target_user_id, __target_uid_id, __is_active, __is_locked, __is_identity_active, __can_login;

	if
		__is_active is null then
		perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
			null,
			_request_context := _request_context,
			_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_not_found'));
		perform error.raise_52103(null, __normalized_email);
	end if;

	if
		not __can_login then
		perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
			__target_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'login_disabled'));
		perform error.raise_52112(__target_user_id);
	end if;

	perform
		unsecure.update_last_used_provider(__target_user_id, 'email');

	if
		not __is_active then
		perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
			__target_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_disabled'));
		perform error.raise_52105(__target_user_id);

	end if;

	if
		not __is_identity_active then
		perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
			__target_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'identity_disabled'));
		perform error.raise_52110(__target_user_id, 'email');
	end if;

	if
		__is_locked then
		perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
			__target_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_locked'));
		perform error.raise_52106(__normalized_email);
	end if;

	perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_logged_in',
		__target_user_id,
		_request_context := _request_context,
		_event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email'));

	return query
		select ui.user_id
				 , ui.code
				 , ui.uuid::text
				 , ui.username
				 , ui.email
				 , ui.display_name
				 , 'email'
				 , uid.password_hash
				 , uid.password_salt
		from auth.user_identity uid
					 inner join auth.user_info ui on uid.user_id = ui.user_id
		where uid.provider_code = 'email'
			and uid.uid = __normalized_email;
end;

$$;

create or replace function auth.ensure_user_info(_created_by text, _user_id bigint, _correlation_id text, _username text, _display_name text, _provider_code text DEFAULT NULL::text, _email text DEFAULT NULL::text, _user_data jsonb DEFAULT NULL::jsonb)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text)
    language plpgsql
as
$$
declare
	__last_id  bigint;
	__username text;
begin

	__username := trim(lower(_username));

	select u.user_id
	from auth.user_info u
	where u.username = __username
	into __last_id;

	if
		__last_id is null then
		select user_id
		from unsecure.create_user_info(_created_by, _user_id, _correlation_id, __username, lower(_email), _display_name,
																	 _provider_code)
		into __last_id;
	end if;

	return query
		select ui.user_id
				 , ui.code
				 , ui.uuid::text
				 , ui.username
				 , ui.email
				 , ui.display_name
		from auth.user_info ui
		where ui.user_id = __last_id;
end;
$$;

create or replace function auth.update_user_data(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider text, _user_data jsonb)
    returns TABLE(__user_id bigint, __user_data_id bigint)
    language plpgsql
as
$$
begin

	--     if
--         __user_id <> _target_user_id then
--         perform auth.has_permission(null, _user_id, 'users.update_user');
--     end if;


end;
$$;

create or replace function auth.get_user_data(_user_id bigint, _correlation_id text, _target_user_id bigint) returns SETOF auth.user_data
    language plpgsql
as
$$
begin

	if
		_user_id <> _target_user_id then
		perform auth.has_permission(_user_id, _correlation_id, 'users.get_data');
	end if;

	select *
	from user_data
	where user_id = _target_user_id;

end;
$$;

create or replace function auth.delete_user_info(_deleted_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_info_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__is_system bool;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'users.delete_user_info', _tenant_id);

	select is_system, tenant_id
	from auth.user_group ug
	where ug.user_group_id = _user_group_id
	into __is_system;

	if
		__is_system is null then
		perform error.raise_52171(_user_group_id);
	end if;

	if
		__is_system then
		perform error.raise_52271(_user_group_id);
	end if;

	return query
		delete
			from auth.user_group
				where tenant_id = _tenant_id
					and user_group_id = _user_group_id
				returning user_group_id;

	perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 13003  -- group_deleted
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text)
			, _tenant_id);
end;
$$;

create or replace function auth.ensure_user_from_provider(_created_by text, _user_id bigint, _correlation_id text, _provider_code text, _provider_uid text, _provider_oid text, _username text, _display_name text, _email text DEFAULT NULL::text, _user_data jsonb DEFAULT NULL::jsonb, _request_context jsonb DEFAULT NULL::jsonb)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text)
    language plpgsql
as
$$
declare
	__target_user_id     bigint;
	__can_login          bool;
	__is_user_active     bool;
	__is_identity_active bool;
	__username           text;
	__display_name       text;
	__email              text;
begin

	if
		lower(_provider_code) = 'email' then
		perform error.raise_52101(_username);
	end if;

	perform
		auth.validate_provider_is_active(_provider_code);

	select uid.user_id, u.is_active, uid.is_active, u.can_login, u.username, u.display_name, u.email
	from auth.user_identity uid
				 inner join auth.user_info u on uid.user_id = u.user_id
	where uid.provider_code = _provider_code
		and (uid.uid = _provider_uid or uid.provider_oid = _provider_oid)
	into __target_user_id, __is_user_active, __is_identity_active, __can_login, __username, __display_name, __email;

	if
		__target_user_id is null then
		-- create user because it does not exists
		select user_id
		from unsecure.create_user_info(_created_by, _user_id, _correlation_id, lower(_username), lower(_email), _display_name,
																	 _provider_code)
		into __target_user_id;

		perform
			unsecure.create_user_identity(_created_by, _user_id, _correlation_id, __target_user_id
				, _provider_code, _provider_uid, _provider_oid, _is_active := true);

		perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_registered',
			__target_user_id,
			_request_context := _request_context,
			_event_data := jsonb_build_object('provider', _provider_code, 'provider_uid', _provider_uid));
	else
		-- update provider_oid
		perform unsecure.update_user_identity_uid_oid(_created_by, _user_id, _correlation_id, __target_user_id
			, _provider_code, _provider_uid
			, _provider_oid);

		-- update basic user data coming from
		if
			(trim(lower(_username)) <> __username
				or _display_name <> __display_name
				or _email <> __email) then
			perform unsecure.update_user_info_basic_data(_created_by, _user_id, _correlation_id, __target_user_id, _username, _display_name,
																									 _email);
		end if;

		if
			not __can_login then
			perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_login_failed',
				__target_user_id,
				_request_context := _request_context,
				_event_data := jsonb_build_object('provider', _provider_code, 'provider_uid', _provider_uid, 'reason', 'login_disabled'));
			perform error.raise_52112(__target_user_id);
		end if;

		if
			not __is_user_active then
			perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_login_failed',
				__target_user_id,
				_request_context := _request_context,
				_event_data := jsonb_build_object('provider', _provider_code, 'provider_uid', _provider_uid, 'reason', 'user_disabled'));
			perform error.raise_52105(__target_user_id);
		end if;

		if
			not __is_identity_active then
			perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_login_failed',
				__target_user_id,
				_request_context := _request_context,
				_event_data := jsonb_build_object('provider', _provider_code, 'provider_uid', _provider_uid, 'reason', 'identity_disabled'));
			perform error.raise_52110(__target_user_id, _provider_code);
		end if;
	end if;

	-- clean all previous uids for the same provider for given user
	delete
	from auth.user_identity
	where user_id = __target_user_id
		and provider_code = _provider_code
		and uid <> _provider_uid;

	perform
		unsecure.update_last_used_provider(__target_user_id, _provider_code);

	perform unsecure.create_user_event(_created_by, _user_id, _correlation_id, 'user_logged_in',
		__target_user_id,
		_request_context := _request_context,
		_event_data := jsonb_build_object('provider', _provider_code, 'provider_uid', _provider_uid));

	return query
		select ui.user_id
				 , ui.code
				 , ui.uuid::text
				 , ui.username
				 , ui.email
				 , ui.display_name
		from auth.user_identity uid
					 inner join auth.user_info ui on uid.user_id = ui.user_id
		where uid.provider_code = _provider_code
			and uid.uid = _provider_uid;
end;
$$;

create or replace function auth.update_user_preferences(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _update_data text)
    returns TABLE(__updated_at timestamp with time zone, __updated_by character varying)
    rows 1
    language plpgsql
as
$$
begin
    if _user_id <> _target_user_id
    then
        perform auth.has_permission(_user_id, _correlation_id, 'users.update_user_data');
    end if;

    return query
        update auth.user_info
            set updated_at = now()
                , updated_by = _updated_by
                , user_preferences = user_preferences || _update_data::jsonb
            where user_id = _target_user_id
            returning updated_at
                , updated_by;
end;
$$;

create or replace function auth.get_user_preferences(_user_id bigint, _correlation_id text, _target_user_id bigint)
    returns TABLE(__value text)
    stable
    rows 1
    language plpgsql
as
$$
begin
    if _user_id <> _target_user_id
    then
        perform auth.has_permission(_user_id, _correlation_id, 'users.get_data');
    end if;

    return query
        select user_preferences::text
        from auth.user_info
        where user_id = _target_user_id;
end;
$$;

create or replace function auth.get_user_by_provider_oid(_user_id bigint, _correlation_id text, _provider_oid text)
    returns TABLE(__user_id bigint, __code text, __uuid text, __username text, __email text, __display_name text)
    language plpgsql
as
$$
begin

	return query
		select ui.user_id
				 , code
				 , uuid::text
				 , username
				 , email
				 , display_name
		from auth.user_identity uid
			left join auth.user_info ui on ui.user_id = uid.user_id
		where uid.provider_oid = _provider_oid;
end;
$$;

create or replace function auth.search_users(
    _user_id bigint,
    _correlation_id text,
    _search_text text default null,
    _user_type_code text default null,
    _is_active boolean default null,
    _is_locked boolean default null,
    _page integer default 1,
    _page_size integer default 30,
    _tenant_id integer default 1
)
    returns TABLE(
        __user_id bigint,
        __code text,
        __uuid text,
        __username text,
        __email text,
        __display_name text,
        __user_type_code text,
        __is_active boolean,
        __is_locked boolean,
        __total_items bigint
    )
    stable
    rows 100
    language plpgsql
    set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers
as
$$
declare
    __search_text text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'users.read_users', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 30), 100);

    return query
        with filtered_users as (
            select ui.user_id
                 , count(*) over () as total_items
            from auth.user_info ui
            where (_user_type_code is null or ui.user_type_code = _user_type_code)
              and (_is_active is null or ui.is_active = _is_active)
              and (_is_locked is null or ui.is_locked = _is_locked)
              and (helpers.is_empty_string(__search_text)
                   or ui.nrm_search_data like '%' || __search_text || '%')
            order by ui.display_name
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select ui.user_id
             , ui.code
             , ui.uuid::text
             , ui.username
             , ui.email
             , ui.display_name
             , ui.user_type_code
             , ui.is_active
             , ui.is_locked
             , fu.total_items
        from filtered_users fu
                 inner join auth.user_info ui on fu.user_id = ui.user_id;
end;
$$;

