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

