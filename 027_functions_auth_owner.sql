/*
 * Auth Owner Functions
 * ====================
 *
 * Ownership management: tenant/group owners
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.has_owner(_user_group_id integer DEFAULT NULL::integer, _tenant_id integer DEFAULT 1) returns boolean
    immutable
    language plpgsql
as
$$
begin
	if exists(select from auth.owner where tenant_id = _tenant_id and user_group_id = _user_group_id) then
		return true;
	end if;

	return false;
end;
$$;

create or replace function auth.is_owner(_user_id bigint, _user_group_id integer DEFAULT NULL::integer, _tenant_id integer DEFAULT 1) returns boolean
    immutable
    language plpgsql
as
$$
begin
	if exists(select
						from auth.owner
						where user_id = _user_id
							and tenant_id = _tenant_id
							and (_user_group_id is null or user_group_id = _user_group_id)) then
		return true;
	end if;

	return false;
end;
$$;

create or replace function auth.create_owner(_created_by text, _user_id bigint, _target_user_id bigint, _user_group_id integer DEFAULT NULL::integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__owner_id bigint)
    rows 1
    language plpgsql
as
$$
begin

	if not auth.is_owner(_user_id, _user_group_id, _tenant_id)
		and not auth.is_owner(_user_id, null, _tenant_id)
	then
		if _user_group_id is not null then
			perform auth.has_permission(_user_id
				, 'tenants.assign_group_owner', _tenant_id);
		else
			perform auth.has_permission(_user_id
				, 'tenants.assign_owner', _tenant_id);
		end if;
	end if;

	return query
		insert into auth.owner (created_by, tenant_id, user_group_id, user_id)
			values (_created_by, _tenant_id, _user_group_id, _target_user_id)
			returning owner_id;

	perform create_journal_message(_created_by, _user_id
			, 11010  -- tenant_user_added
			, 'tenant', _tenant_id
			, jsonb_build_object('username', _target_user_id::text, 'tenant_title', _tenant_id::text
				, 'user_group_id', _user_group_id, 'action', 'owner_added')
			, _tenant_id);
end;
$$;

create or replace function auth.delete_owner(_deleted_by text, _user_id bigint, _target_user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
	if not auth.is_owner(_user_id, _user_group_id, _tenant_id)
		and not auth.is_owner(_user_id, null, _tenant_id)
	then
		if _user_group_id is not null then
			perform auth.has_permission(_user_id
				, 'tenants.assign_group_owner', _tenant_id);
		else
			perform auth.has_permission(_user_id
				, 'tenants.assign_owner', _tenant_id);
		end if;
	end if;

	delete
	from auth.owner
	where user_id = _target_user_id
		and tenant_id = _tenant_id
		and user_group_id = _user_group_id;

	perform create_journal_message(_deleted_by, _user_id
			, 11011  -- tenant_user_removed
			, 'tenant', _tenant_id
			, jsonb_build_object('username', _target_user_id::text, 'tenant_title', _tenant_id::text
				, 'user_group_id', _user_group_id, 'action', 'owner_removed')
			, _tenant_id);
end;
$$;

