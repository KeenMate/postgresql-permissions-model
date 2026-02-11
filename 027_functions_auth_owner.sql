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

	perform
		add_journal_msg(_created_by, _user_id
			, format('User: %s added new tenant/group owner in tenant: %s'
											, _created_by, _tenant_id)
			, 'tenant', _tenant_id
			, array ['user_group_id', _user_group_id::text]
			, 50004
			, _tenant_id := _tenant_id);
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

	perform
		add_journal_msg(_deleted_by, _user_id
			, format('User: %s deleted new tenant/group owner in tenant: %s'
											, _deleted_by, _tenant_id)
			, 'tenant', _tenant_id
			, array ['user_group_id', _user_group_id::text]
			, 50004
			, _tenant_id := _tenant_id);
end;
$$;

