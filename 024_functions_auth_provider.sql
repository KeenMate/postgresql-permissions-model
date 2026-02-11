/*
 * Auth Provider Functions
 * =======================
 *
 * Identity provider management: create/update/enable/disable providers
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.validate_provider_is_active(_provider_code text) returns void
    language plpgsql
as
$$
begin
	if
		exists(select from auth.provider where code = _provider_code and is_active = false) then
		perform error.raise_52107(_provider_code);


	end if;
end;
$$;

create or replace function auth.create_provider(_created_by text, _user_id bigint, _provider_code text, _provider_name text, _is_active boolean DEFAULT true)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__last_id int;
begin

	perform
		auth.has_permission(_user_id, 'providers.create_provider');

	insert into auth.provider (created_by, updated_by, code, name, is_active)
	values (_created_by, _created_by, _provider_code, _provider_name, _is_active)
	returning provider_id
		into __last_id;

	return query
		select __last_id;

	perform
		add_journal_msg(_created_by, _user_id
			, format('User: %s created new authentication provider: %s'
											, _created_by, _provider_name)
			, 'provider', __last_id
			, array ['provider_code', _provider_code, 'provider_name', _provider_name, 'is_active', _is_active::text]
			, 50011
			, _tenant_id := 1);
end;
$$;

create or replace function auth.update_provider(_updated_by text, _user_id bigint, _provider_id integer, _provider_code text, _provider_name text, _is_active boolean DEFAULT true)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
begin

	perform
		auth.has_permission(_user_id, 'providers.update_provider');

	return query
		update auth.provider
			set updated_at = now(),
				updated_by = _updated_by, code = _provider_code, name = _provider_name, is_active = _is_active
			where provider_id = _provider_id
			returning provider_id;

	perform
		add_journal_msg(_updated_by, _user_id
			, format('User: %s updated authentication provider: %s'
											, _updated_by, _provider_name)
			, 'provider', _provider_id
			, array ['provider_code', _provider_code, 'provider_name', _provider_name, 'is_active', _is_active::text]
			, 50012
			, _tenant_id := 1);
end;
$$;

create or replace function auth.delete_provider(_deleted_by text, _user_id bigint, _provider_code text)
    returns TABLE(__user_id bigint, __username text, __display_name text)
    rows 1
    language plpgsql
as
$$
declare
	__provider_id int;
begin

	perform
		auth.has_permission(_user_id, 'providers.delete_provider');

	return query
		delete
			from auth.provider
				where code = _provider_code
				returning __provider_id;

	perform
		add_journal_msg(_deleted_by, _user_id
			, format('User: %s deleted authentication provider: %s'
											, _deleted_by, _provider_code)
			, 'provider', __provider_id
			, null
			, 50013
			, _tenant_id := 1);
end;
$$;

create or replace function auth.enable_provider(_updated_by text, _user_id bigint, _provider_code text)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__provider_id int;
begin

	perform
		auth.has_permission(_user_id, 'providers.update_provider');

	return query
		update auth.provider
			set is_active = true
			where code = _provider_code
			returning provider_id;

	perform
		add_journal_msg(_updated_by, _user_id
			, format('User: %s enabled authentication provider: %s'
											, _updated_by, _provider_code)
			, 'provider', __provider_id
			, null
			, 50014
			, _tenant_id := 1);
end;
$$;

create or replace function auth.disable_provider(_updated_by text, _user_id bigint, _provider_code text)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__provider_id int;
begin

	perform
		auth.has_permission(_user_id, 'providers.update_provider');

	return query
		update auth.provider
			set is_active = false
			where code = _provider_code
			returning provider_id;

	perform
		add_journal_msg(_updated_by, _user_id
			, format('User: %s disabled authentication provider: %s'
											, _updated_by, _provider_code)
			, 'provider', __provider_id
			, null
			, 50015
			, _tenant_id := 1);
end;
$$;

create or replace function auth.get_provider_users(_requested_by text, _user_id bigint, _provider_code text)
    returns TABLE(__user_id bigint, __user_identity_id bigint, __username text, __display_name text)
    language plpgsql
as
$$
declare
	__provider_id int;
begin
	perform
		auth.has_permission(_user_id, 'manage_provider.get_users');

	select provider_id
	from auth.provider
	where code = _provider_code
	into __provider_id;

	return query
		select ui.user_id, uid.user_identity_id, ui.username, ui.display_name
		from auth.user_identity uid
					 inner join auth.user_info ui on uid.user_id = ui.user_id
		where uid.provider_code = _provider_code
		order by ui.display_name;

	perform
		add_journal_msg(_requested_by, _user_id
			, format('User: %s requested a list of all users for authentication provider: %s'
											, _requested_by, _provider_code)
			, 'provider', __provider_id
			, null
			, 50016
			, _tenant_id := 1);
end;
$$;

