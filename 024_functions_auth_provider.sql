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

create or replace function auth.validate_provider_allows_group_mapping(_provider_code text) returns void
    language plpgsql
as
$$
begin
	if
		exists(select from auth.provider where code = _provider_code and allows_group_mapping = false) then
		perform error.raise_33016(_provider_code);
	end if;
end;
$$;

create or replace function auth.validate_provider_allows_group_sync(_provider_code text) returns void
    language plpgsql
as
$$
begin
	if
		exists(select from auth.provider where code = _provider_code and allows_group_sync = false) then
		perform error.raise_33017(_provider_code);
	end if;
end;
$$;

create or replace function auth.ensure_provider(_created_by text, _user_id bigint, _correlation_id text, _provider_code text, _provider_name text, _is_active boolean default true, _allows_group_mapping boolean default false, _allows_group_sync boolean default false)
    returns table(__provider_id integer, __is_new boolean)
    rows 1
    language plpgsql
as
$$
declare
    __existing_id int;
    __new_id int;
begin
    select provider_id
    from auth.provider
    where code = _provider_code
    into __existing_id;

    if __existing_id is not null then
        return query select __existing_id, false;
        return;
    end if;

    select p.__provider_id
    from auth.create_provider(_created_by, _user_id, _correlation_id, _provider_code, _provider_name, _is_active, _allows_group_mapping, _allows_group_sync) p
    into __new_id;

    return query select __new_id, true;
end;
$$;

create or replace function auth.create_provider(_created_by text, _user_id bigint, _correlation_id text, _provider_code text, _provider_name text, _is_active boolean DEFAULT true, _allows_group_mapping boolean default false, _allows_group_sync boolean default false)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__last_id int;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'providers.create_provider');

	insert into auth.provider (created_by, updated_by, code, name, is_active, allows_group_mapping, allows_group_sync)
	values (_created_by, _created_by, _provider_code, _provider_name, _is_active, _allows_group_mapping, _allows_group_sync)
	returning provider_id
		into __last_id;

	return query
		select __last_id;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 16001  -- provider_created
			, 'provider', __last_id
			, jsonb_build_object('provider_code', _provider_code, 'provider_name', _provider_name
				, 'is_active', _is_active
				, 'allows_group_mapping', _allows_group_mapping, 'allows_group_sync', _allows_group_sync)
			, 1);
end;
$$;

create or replace function auth.update_provider(_updated_by text, _user_id bigint, _correlation_id text, _provider_id integer, _provider_code text, _provider_name text, _is_active boolean DEFAULT true, _allows_group_mapping boolean default false, _allows_group_sync boolean default false)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'providers.update_provider');

	return query
		update auth.provider
			set updated_at = now(),
				updated_by = _updated_by, code = _provider_code, name = _provider_name, is_active = _is_active,
				allows_group_mapping = _allows_group_mapping, allows_group_sync = _allows_group_sync
			where provider_id = _provider_id
			returning provider_id;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 16002  -- provider_updated
			, 'provider', _provider_id
			, jsonb_build_object('provider_code', _provider_code, 'provider_name', _provider_name
				, 'is_active', _is_active
				, 'allows_group_mapping', _allows_group_mapping, 'allows_group_sync', _allows_group_sync)
			, 1);
end;
$$;

create or replace function auth.delete_provider(_deleted_by text, _user_id bigint, _correlation_id text, _provider_code text)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	___provider_id int;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'providers.delete_provider');

	delete
		from auth.provider
			where code = _provider_code
			returning provider_id
				into ___provider_id;

	return query
		select ___provider_id;

	perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 16003  -- provider_deleted
			, 'provider', ___provider_id
			, jsonb_build_object('provider_code', _provider_code)
			, 1);
end;
$$;

create or replace function auth.enable_provider(_updated_by text, _user_id bigint, _correlation_id text, _provider_code text)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	___provider_id int;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'providers.update_provider');

	update auth.provider
		set is_active = true
		where code = _provider_code
		returning provider_id
			into ___provider_id;

	return query
		select ___provider_id;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 16004  -- provider_enabled
			, 'provider', ___provider_id
			, jsonb_build_object('provider_code', _provider_code)
			, 1);
end;
$$;

create or replace function auth.disable_provider(_updated_by text, _user_id bigint, _correlation_id text, _provider_code text)
    returns TABLE(__provider_id integer)
    rows 1
    language plpgsql
as
$$
declare
	___provider_id int;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'providers.update_provider');

	update auth.provider
		set is_active = false
		where code = _provider_code
		returning provider_id
			into ___provider_id;

	return query
		select ___provider_id;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 16005  -- provider_disabled
			, 'provider', ___provider_id
			, jsonb_build_object('provider_code', _provider_code)
			, 1);
end;
$$;

create or replace function auth.get_provider_users(_requested_by text, _user_id bigint, _correlation_id text, _provider_code text)
    returns TABLE(__user_id bigint, __user_identity_id bigint, __username text, __display_name text)
    language plpgsql
as
$$
declare
	__provider_id int;
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'manage_provider.get_users');

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

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function auth.get_providers(_user_id bigint, _correlation_id text, _is_active boolean default null, _allows_group_mapping boolean default null, _allows_group_sync boolean default null, _search text default null)
    returns table(__provider_id integer, __code text, __name text, __is_active boolean, __allows_group_mapping boolean, __allows_group_sync boolean)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'providers');

	return query
		select p.provider_id
			 , p.code
			 , p.name
			 , p.is_active
			 , p.allows_group_mapping
			 , p.allows_group_sync
		from auth.provider p
		where (_is_active is null or p.is_active = _is_active)
		  and (_allows_group_mapping is null or p.allows_group_mapping = _allows_group_mapping)
		  and (_allows_group_sync is null or p.allows_group_sync = _allows_group_sync)
		  and (_search is null or p.name ilike '%' || _search || '%' or p.code ilike '%' || _search || '%')
		order by p.code;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

