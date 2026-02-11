/*
 * Trigger Functions
 * =================
 *
 * Database trigger functions for calculated fields and data integrity
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function triggers.calculate_user_data_search_values(_user_data auth.user_data) returns text
    language plpgsql
as
$$
begin

	return null;
end ;
$$;

create or replace function triggers.calculate_user_data() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then

		new.nrm_search_data = triggers.calculate_user_data_search_values(new);

		return new;
	end if;
end ;
$$;

create or replace function triggers.calculate_user_info_search_values(_user_info auth.user_info) returns text
    language plpgsql
as
$$
begin

	return concat_ws(' ', helpers.normalize_text(_user_info.username)
		, helpers.normalize_text(_user_info.display_name)
		, helpers.normalize_text(_user_info.email)
		);
end;
$$;

create or replace function triggers.calculate_user_info() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then

		new.nrm_search_data = triggers.calculate_user_info_search_values(new);

		return new;
	end if;
end ;
$$;

-- Tenant search trigger functions
create or replace function triggers.calculate_tenant_search_values(_tenant auth.tenant) returns text
    language plpgsql
as
$$
begin
	return concat_ws(' ', helpers.normalize_text(_tenant.title)
		, helpers.normalize_text(_tenant.code)
		);
end;
$$;

create or replace function triggers.calculate_tenant() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then
		new.nrm_search_data = triggers.calculate_tenant_search_values(new);
		return new;
	end if;
end ;
$$;

-- User group search trigger functions
create or replace function triggers.calculate_user_group_search_values(_user_group auth.user_group) returns text
    language plpgsql
as
$$
begin
	return concat_ws(' ', helpers.normalize_text(_user_group.title)
		, helpers.normalize_text(_user_group.code)
		);
end;
$$;

create or replace function triggers.calculate_user_group() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then
		new.nrm_search_data = triggers.calculate_user_group_search_values(new);
		return new;
	end if;
end ;
$$;

-- Permission search trigger functions
create or replace function triggers.calculate_permission_search_values(_permission auth.permission) returns text
    language plpgsql
as
$$
begin
	return concat_ws(' ', helpers.normalize_text(_permission.title)
		, helpers.normalize_text(_permission.code)
		, helpers.normalize_text(_permission.full_code::text)
		);
end;
$$;

create or replace function triggers.calculate_permission() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then
		new.nrm_search_data = triggers.calculate_permission_search_values(new);
		return new;
	end if;
end ;
$$;

-- Permission set search trigger functions
create or replace function triggers.calculate_perm_set_search_values(_perm_set auth.perm_set) returns text
    language plpgsql
as
$$
begin
	return concat_ws(' ', helpers.normalize_text(_perm_set.title)
		, helpers.normalize_text(_perm_set.code)
		);
end;
$$;

create or replace function triggers.calculate_perm_set() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then
		new.nrm_search_data = triggers.calculate_perm_set_search_values(new);
		return new;
	end if;
end ;
$$;

-- API key search trigger functions
create or replace function triggers.calculate_api_key_search_values(_api_key auth.api_key) returns text
    language plpgsql
as
$$
begin
	return concat_ws(' ', helpers.normalize_text(_api_key.title)
		, helpers.normalize_text(_api_key.description)
		);
end;
$$;

create or replace function triggers.calculate_api_key() returns trigger
    language plpgsql
as
$$
begin
	if tg_op = 'INSERT' or tg_op = 'UPDATE' then
		new.nrm_search_data = triggers.calculate_api_key_search_values(new);
		return new;
	end if;
end ;
$$;

-- Trigger creation statements
create trigger trg_auth_calculate_user_data
	before insert or update
	on auth.user_data
	for each row
execute function triggers.calculate_user_data();

create trigger trg_auth_calculate_user_info
	before insert or update
	on auth.user_info
	for each row
execute function triggers.calculate_user_info();

create trigger trg_auth_calculate_tenant
	before insert or update
	on auth.tenant
	for each row
execute function triggers.calculate_tenant();

create trigger trg_auth_calculate_user_group
	before insert or update
	on auth.user_group
	for each row
execute function triggers.calculate_user_group();

create trigger trg_auth_calculate_permission
	before insert or update
	on auth.permission
	for each row
execute function triggers.calculate_permission();

create trigger trg_auth_calculate_perm_set
	before insert or update
	on auth.perm_set
	for each row
execute function triggers.calculate_perm_set();

create trigger trg_auth_calculate_api_key
	before insert or update
	on auth.api_key
	for each row
execute function triggers.calculate_api_key();

