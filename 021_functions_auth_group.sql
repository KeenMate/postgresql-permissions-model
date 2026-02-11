/*
 * Auth Group Functions
 * ====================
 *
 * Group management: create/update groups, members, mappings, external/hybrid
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.is_group_member(_user_id bigint, _user_group_id integer DEFAULT NULL::integer, _tenant_id integer DEFAULT 1) returns boolean
    immutable
    language plpgsql
as
$$
begin
	if exists(select
						from auth.user_group_members
						where user_id = _user_id
							and tenant_id = _tenant_id
							and user_group_id = _user_group_id) then
		return true;
	end if;

	return false;
end;
$$;

create or replace function auth.can_manage_user_group(_user_id bigint, _user_group_id integer, _permission text, _tenant_id integer DEFAULT 1) returns boolean
    immutable
    language plpgsql
as
$$
declare
	__can_members_manage_others bool;
	__has_owner                 bool;
	__is_member                 bool;
begin
	select can_members_manage_others, member_id is not null
	from auth.user_group ug
				 left join auth.user_group_member ugm on ug.user_group_id = ugm.group_id
	where user_group_id = _user_group_id
		and ugm.user_id = _user_id
	into __can_members_manage_others, __is_member;

	if not (__can_members_manage_others and __is_member) then
		__has_owner := auth.has_owner(_user_group_id, _tenant_id);

		if not (auth.is_owner(_user_id, null, _tenant_id)) then
			if __has_owner then
				-- if user group has owner and user is not one of them throw 52281 exception
				if not auth.is_owner(_user_id, _user_group_id, _tenant_id) then
					perform error.raise_52401(_user_id, _user_group_id, _tenant_id);
				end if;
			else
				-- when there is no owner anybody with the right permission can add new members
				perform auth.has_permission(_user_id, _permission, _tenant_id);
			end if;
		end if;
	end if;

	return true;
end;
$$;

create or replace function auth.create_user_group(_created_by text, _user_id bigint, _title text, _is_assignable boolean DEFAULT true, _is_active boolean DEFAULT true, _is_external boolean DEFAULT false, _is_default boolean DEFAULT false, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id,
												'groups.create_group', _tenant_id);

	return query
		select *
		from unsecure.create_user_group(_created_by, _user_id, _title
			, _is_assignable, _is_active, _is_external, false,
																		_is_default, _tenant_id);
end ;
$$;

create or replace function auth.update_user_group(_updated_by text, _user_id bigint, _user_group_id integer, _title text, _is_assignable boolean, _is_active boolean, _is_external boolean, _is_default boolean, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	return query
		update auth.user_group
			set updated_by = _updated_by
				, updated_at = now()
				, title = _title
				, is_assignable = _is_assignable
				, is_active = _is_active
				, is_external = _is_external
				, is_default = _is_default
			where tenant_id = _tenant_id
				and user_group_id = _user_group_id
			returning user_group_id;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _title, 'is_default', _is_default
				, 'is_assignable', _is_assignable, 'is_active', _is_active, 'is_external', _is_external)
			, _tenant_id);
end;
$$;

create or replace function auth.enable_user_group(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __is_active boolean, __is_assignable boolean, __updated_at timestamp with time zone, __updated_by text)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	return query
		update auth.user_group
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = true
			where tenant_id = _tenant_id
				and user_group_id = _user_group_id
			returning user_group_id
				, is_active
				, is_assignable
				, updated_at
				, updated_by;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (enabled)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text, 'action', 'enabled')
			, _tenant_id);
end;
$$;

create or replace function auth.disable_user_group(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __is_active boolean, __is_assignable boolean, __updated_at timestamp with time zone, __updated_by text)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	return query
		update auth.user_group
			set updated_by = _updated_by
				, updated_at = now()
				, is_active = false
			where tenant_id = _tenant_id
				and user_group_id = _user_group_id
			returning user_group_id
				, is_active
				, is_assignable
				, updated_at
				, updated_by;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (disabled)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text, 'action', 'disabled')
			, _tenant_id);
end;
$$;

create or replace function auth.lock_user_group(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __is_active boolean, __is_assignable boolean, __updated_at timestamp with time zone, __updated_by text)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.lock_group', _tenant_id);

	return query
		update auth.user_group
			set updated_by = _updated_by
				, updated_at = now()
				, is_assignable = false
			where tenant_id = _tenant_id
				and user_group_id = _user_group_id
			returning user_group_id
				, is_active
				, is_assignable
				, updated_at
				, updated_by;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (locked)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text, 'action', 'locked')
			, _tenant_id);
end;
$$;

create or replace function auth.unlock_user_group(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __is_active boolean, __is_assignable boolean, __updated_at timestamp with time zone, __updated_by text)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	return query
		update auth.user_group
			set updated_by = _updated_by
				, updated_at = now()
				, is_assignable = true
			where tenant_id = _tenant_id
				and user_group_id = _user_group_id
			returning user_group_id
				, is_active
				, is_assignable
				, updated_at
				, updated_by;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (unlocked)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text, 'action', 'unlocked')
			, _tenant_id);
end;
$$;

create or replace function auth.delete_user_group(_deleted_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__is_system bool;
begin

	perform
		auth.has_permission(_user_id, 'groups.delete_group', _tenant_id);

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

	perform create_journal_message(_deleted_by, _user_id
			, 13003  -- group_deleted
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text)
			, _tenant_id);
end;
$$;

create or replace function auth.delete_user_group_member(_deleted_by text, _user_id bigint, _user_group_id integer, _target_user_id bigint, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
declare
	__user_group_code text;
	__user_upn        text;
begin
	perform auth.can_manage_user_group(_user_id, _user_group_id, 'groups.delete_member', _tenant_id);

	select code
	from auth.user_group
	where user_group_id = _user_group_id
	into __user_group_code;

	select code
	from auth.user_info
	where user_id = _target_user_id
	into __user_upn;

	delete
	from auth.user_group_member
	where group_id = _user_group_id
		and user_id = _target_user_id;


	perform create_journal_message(_deleted_by, _user_id
			, 13011  -- group_member_removed
			, 'group', _user_group_id
			, jsonb_build_object('username', __user_upn, 'group_title', __user_group_code
				, 'target_user_id', _target_user_id)
			, _tenant_id);
end;
$$;

create or replace function auth.get_user_group_mappings(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns SETOF auth.user_group_mapping
    language plpgsql
as
$$
begin

	perform auth.has_permission(_user_id, 'groups.get_mapping', _tenant_id);

	return query select *
							 from auth.user_group_mapping ugm
							 where ugm.group_id = _user_group_id;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function auth.create_user_group_mapping(_created_by text, _user_id bigint, _user_group_id integer, _provider_code text, _mapped_object_id text DEFAULT NULL::text, _mapped_object_name text DEFAULT NULL::text, _mapped_role text DEFAULT NULL::text, _tenant_id integer DEFAULT 1)
    returns TABLE(__ug_mapping_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__is_group_active bool;
begin

	if
		_mapped_object_id is null and _mapped_role is null then
		perform error.raise_52174();

	end if;

	perform
		auth.has_permission(_user_id, 'groups.create_mapping', _tenant_id);

	select is_active, tenant_id
	from auth.user_group ug
	where ug.user_group_id = _user_group_id
	into __is_group_active;

	if
		__is_group_active is null then
		perform error.raise_52171(_user_group_id);
	end if;

	return query insert into auth.user_group_mapping (created_by, group_id, provider_code, mapped_object_id,
																										mapped_object_name,
																										mapped_role)
		values ( _created_by, _user_group_id, _provider_code, lower(_mapped_object_id), _mapped_object_name
					 , lower(_mapped_role))
		returning ug_mapping_id;


	with affected_users as (select user_id
													from auth.user_identity uid
													where lower(_mapped_object_id) = any (provider_groups)
														 or lower(_mapped_object_id) = any (provider_roles))
	update auth.user_permission_cache
	set updated_by      = _created_by
		, updated_at      = now()
		, expiration_date = now() - '1 sec':: interval
	where user_id in (select user_id
										from affected_users);


	perform create_journal_message(_created_by, _user_id
			, 13020  -- group_mapping_created
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text
				, 'mapping_name', coalesce(_mapped_object_name, _mapped_object_id, _mapped_role)
				, 'provider_code', _provider_code
				, 'mapped_object_id', _mapped_object_id, 'mapped_role', _mapped_role)
			, _tenant_id);
end;
$$;

create or replace function auth.delete_user_group_mapping(_deleted_by text, _user_id bigint, _user_group_mapping_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
declare
	__user_group_id      int;
	__provider_code      text;
	__mapped_object_id   text;
	__mapped_object_name text;
	__mapped_role        text;
begin
	perform
		auth.has_permission(_user_id, 'groups.delete_mapping', _tenant_id);

	-- expire user_permission_cache for affected users
	with affected_users as (select user_id
													from auth.user_group_member ugm
													where ugm.mapping_id = _user_group_mapping_id)
	update auth.user_permission_cache
	set updated_by      = _deleted_by
		, updated_at      = now()
		, expiration_date = now() - '1 sec':: interval
	where user_id in (select user_id
										from affected_users);

	delete
	from auth.user_group_mapping
	where ug_mapping_id = _user_group_mapping_id
	returning group_id, provider_code, mapped_object_id, mapped_object_name, mapped_role
		into __user_group_id, __provider_code, __mapped_object_id, __mapped_object_name, __mapped_role;


	perform create_journal_message(_deleted_by, _user_id
			, 13021  -- group_mapping_deleted
			, 'group', __user_group_id
			, jsonb_build_object('group_title', __user_group_id::text
				, 'mapping_name', coalesce(__mapped_object_name, __mapped_object_id, __mapped_role)
				, 'provider_code', __provider_code
				, 'mapped_object_id', __mapped_object_id, 'mapped_role', __mapped_role)
			, _tenant_id);
end;
$$;

create or replace function auth.create_external_user_group(_created_by text, _user_id bigint, _title text, _provider text, _is_assignable boolean DEFAULT true, _is_active boolean DEFAULT true, _mapped_object_id text DEFAULT NULL::text, _mapped_object_name text DEFAULT NULL::text, _mapped_role text DEFAULT NULL::text, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__last_id int;
begin
	perform
		auth.has_permission(_user_id,
												'groups.create_group', _tenant_id);


	select *
	from unsecure.create_user_group(_created_by, _user_id, _title
		, _is_assignable, _is_active, true,
																	false, _tenant_id := _tenant_id)
	into __last_id;

	perform
		auth.create_user_group_mapping(_created_by, _user_id, __last_id, _provider, _mapped_object_id,
																	 _mapped_object_name, _mapped_role, _tenant_id := _tenant_id);

	return query
		select __last_id;
end ;
$$;

create or replace function auth.set_user_group_as_hybrid(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	update auth.user_group
	set updated_at  = now()
		, updated_by  = _updated_by
		, is_external = false
	where user_group_id = _user_group_id;

	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (set as hybrid)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', _user_group_id::text, 'action', 'set_hybrid')
			, _tenant_id);
end;
$$;

create or replace function auth.get_user_group_by_id(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __tenant_id integer, __title text, __code text, __is_system boolean, __is_external boolean, __is_assignable boolean, __is_active boolean, __is_default boolean)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.get_group', _tenant_id);

	return query
		select *
		from unsecure.get_user_group_by_id(_requested_by, _user_id, _user_group_id, _tenant_id);
end
$$;

create or replace function auth.create_user_group_member(_created_by text, _user_id bigint, _user_group_id integer, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_member_id bigint)
    rows 1
    language plpgsql
as
$$
begin
	perform auth.can_manage_user_group(_user_id, _user_group_id, 'groups.create_member', _tenant_id);

	return query
		select *
		from unsecure.create_user_group_member(_created_by, _user_id
			, _user_group_id, _target_user_id, _tenant_id);
end;

$$;

create or replace function auth.get_user_group_members(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__created timestamp with time zone, __created_by text, __member_id bigint, __member_type_code text, __user_id bigint, __user_display_name text, __user_is_system boolean, __user_is_active boolean, __user_is_locked boolean, __mapping_id integer, __mapping_mapped_object_name text, __mapping_provider_code text)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, 'groups.get_members', _tenant_id);

	return query
		select *
		from unsecure.get_user_group_members(_requested_by, _user_id
			, _user_group_id, _tenant_id);
end;
$$;

create or replace function auth.set_user_group_as_external(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
declare
	__user_group_code text;
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	delete
	from auth.user_group_member ugm
	where ugm.group_id = _user_group_id
		and ugm.member_type_code = 'manual';

	update auth.user_group
	set updated_at  = now()
		, updated_by  = _updated_by
		, is_external = true
	where user_group_id = _user_group_id
	returning code
		into __user_group_code;


	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (set as external)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', __user_group_code, 'action', 'set_external')
			, _tenant_id);
end;
$$;

create or replace function auth.set_user_group_as_internal(_updated_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
declare
	__user_group_code text;
begin
	perform
		auth.has_permission(_user_id, 'groups.update_group', _tenant_id);

	-- Delete all external/sync members (keep manual members intact)
	delete
	from auth.user_group_member ugm
	where ugm.group_id = _user_group_id
		and ugm.member_type_code <> 'manual';

	-- Delete all mappings for this group
	delete
	from auth.user_group_mapping ugm
	where ugm.group_id = _user_group_id;

	update auth.user_group
	set updated_at  = now()
		, updated_by  = _updated_by
		, is_external = false
		, is_synced   = false
		, create_missing_users_on_sync = false
	where user_group_id = _user_group_id
	returning code
		into __user_group_code;


	perform create_journal_message(_updated_by, _user_id
			, 13002  -- group_updated (set as internal)
			, 'group', _user_group_id
			, jsonb_build_object('group_title', __user_group_code, 'action', 'set_internal')
			, _tenant_id);
end;
$$;

create or replace function auth.get_user_assigned_groups(_user_id bigint, _target_user_id bigint)
    returns TABLE(__user_group_member_id bigint, __user_group_id integer, __user_group_code text, __user_group_title text, __user_group_member_type_code text, __user_group_mapping_id integer)
    stable
    language plpgsql
as
$$
begin

	if (_user_id != _target_user_id) then
		perform auth.has_permission(_user_id, 'users.read_user_group_memberships');
	end if;

	return query
		select ugm.member_id, ugm.group_id, ug.code, ug.title, ugm.member_type_code, ugm.mapping_id
		from auth.user_group_member ugm
					 inner join auth.user_group ug on ug.user_group_id = ugm.group_id
		where ugm.user_id = _target_user_id
		order by ug.title;

end;
$$;

create or replace function auth.get_user_groups_to_sync(_user_id bigint)
    returns TABLE(__user_group_id integer, __user_group_mapping_id integer, __title text, __code text, __provider_code text, __mapped_object_id text, __mapped_object_name text)
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, 'groups.get_groups');

	return query
		select ug.user_group_id,
					 ugm.ug_mapping_id,
					 ug.title,
					 ug.code,
					 ugm.provider_code,
					 ugm.mapped_object_id,
					 ugm.mapped_object_name
		from auth.user_group ug
					 inner join auth.user_group_mapping ugm on ug.user_group_id = ugm.group_id
		where ug.is_synced
		order by provider_code, code;
end;
$$;

create or replace function auth.process_external_group_member_sync_by_mapping(_run_by text, _user_id bigint, _user_group_mapping_id integer)
    returns TABLE(__user_group_id integer, __user_group_mapping_id integer, __state_code text, __user_id bigint, __upn text)
    language plpgsql
as
$$
declare
	__create_missing_users_on_sync bool;
	__user_group_id                int;
	__provider_code                text;
	__to_create_number             bigint;
begin

	--   perform auth.has_permission(_user_id, '');

	select ugm.group_id, create_missing_users_on_sync, provider_code
	from auth.user_group_mapping ugm
				 inner join auth.user_group ug on ugm.group_id = ug.user_group_id
	where ugm.ug_mapping_id = _user_group_mapping_id
	into __user_group_id, __create_missing_users_on_sync, __provider_code;

	create temporary table __temp_current_members as
	select ui.user_id, ui.username as upn
	from auth.user_group_member ugm
				 inner join auth.user_info ui on ugm.user_id = ui.user_id
	where ugm.mapping_id = _user_group_mapping_id;

	create temporary table __temp_ensure_users as
	select egm.external_group_member_id,
				 egm.member_upn,
				 egm.member_display_name,
				 egm.member_email,
				 egm.user_group_mapping_id
	from stage.external_group_member egm
				 left join auth.user_info ui on lower(egm.member_upn) = ui.username
	where egm.user_group_mapping_id = _user_group_mapping_id
		and ui.user_id is null;

	create temporary table __temp_members_comparison as
	select case
					 when current_members.user_id is null
						 then 'create'
					 else 'update' end as operation,
				 ui.user_id,
				 egm.user_group_mapping_id
	from stage.external_group_member egm
				 inner join auth.user_info ui on lower(egm.member_upn) = ui.username
				 left join __temp_current_members as current_members on lower(egm.member_upn) = current_members.upn
	where egm.user_group_mapping_id = _user_group_mapping_id;

	select count(1)
	from __temp_members_comparison
	where operation = 'create'
	into __to_create_number;

	create temporary table __temp_ensured_users as
	select user_group_mapping_id,
				 created_user.__user_id user_id
	from __temp_ensure_users eu,
			 auth.ensure_user_info(_run_by, _user_id, member_upn,
														 member_display_name, __provider_code, member_email) created_user
	where __create_missing_users_on_sync;


	return query
		with combined_create_users as materialized (select user_group_mapping_id,
																											 user_id
																								from __temp_ensured_users
																								union
																								select user_group_mapping_id,
																											 user_id
																								from __temp_members_comparison cm
																								where operation = 'create'),

				 created_members as materialized (
					 insert into auth.user_group_member (created_by, group_id, user_id, mapping_id, member_type_code)
						 select _run_by, __user_group_id, cu.user_id, cu.user_group_mapping_id, 'sync'
						 from combined_create_users cu
						 returning user_id),
				 updated_members as materialized (
					 update auth.user_group_member
						 set member_type_code = 'sync'
						 where mapping_id = _user_group_mapping_id and member_type_code != 'sync' and
									 user_id in (select user_id from __temp_members_comparison where operation = 'update')
						 returning user_id),
				 combined_results as (select 'created' operation, eu.user_id
															from __temp_ensured_users eu
															union
															select 'created' operation, cm.user_id
															from created_members cm
															union
															select 'updated', um.user_id
															from updated_members um)
		select __user_group_id,
					 __user_group_mapping_id,
					 operation,
					 ui.user_id,
					 ui.username
		from combined_results cr
					 inner join auth.user_info ui on cr.user_id = ui.user_id;

	drop table if exists __temp_ensure_users;
	drop table if exists __temp_ensured_users;
	drop table if exists __temp_current_members;
	drop table if exists __temp_members_comparison;
end;
$$;

create or replace function auth.process_external_group_member_sync(_run_by text, _user_id bigint, _user_group_id integer DEFAULT NULL::integer)
    returns TABLE(__user_group_id integer, __user_group_mapping_id integer, __state_code text, __user_id bigint, __upn text)
    language plpgsql
as
$$
declare
	__group_row  record;
	__mapping_id int;
begin

	--   perform auth.has_permission(_user_id, '');

	create temporary table __temp_external_group_sync
	(
		__user_group_id         int,
		__user_group_mapping_id int,
		__state_code            text,
		__user_id               bigint,
		__upn                   text
	);

	for __group_row in
		select egm.user_group_id, array_agg(distinct egm.user_group_mapping_id) as mapping_ids
		from stage.external_group_member egm
					 inner join auth.user_group ug on egm.user_group_id = ug.user_group_id
		where (_user_group_id is null || ug.user_group_id = _user_group_id)
			and ug.is_synced -- if the user group is not synced, it won't be processed
		group by egm.user_group_id
		order by egm.user_group_id
		loop
			raise notice 'Processing external user group members for id: %', __group_row.user_group_id;
			foreach __mapping_id in array __group_row.mapping_ids
				loop
					raise notice 'Processing external user group members mapping for id: %', __mapping_id;
					insert into __temp_external_group_sync
					select *
					from auth.process_external_group_member_sync_by_mapping(_run_by, _user_id, __mapping_id);

					with deleted_users as materialized (
						delete
							from auth.user_group_member
								where user_group_member.member_id in
											(select ugm.member_id
											 from auth.user_group_member ugm
															inner join auth.user_info u on u.user_id = ugm.user_id
															left join stage.external_group_member egm
																				on ugm.mapping_id = egm.user_group_mapping_id and
																					 lower(egm.member_upn) = u.username
											 where ugm.mapping_id = __mapping_id
												 and egm.external_group_member_id is null)
								returning user_id)
					insert
					into __temp_external_group_sync
					select __user_group_id,
								 __user_group_mapping_id,
								 'deleted',
								 ui.user_id,
								 ui.username
					from deleted_users cr
								 inner join auth.user_info ui on cr.user_id = ui.user_id;

				end loop;

			-- 			create temporary table __temp_delete_members as
-- 			select current_members.user_id
-- 			from __temp_current_members as current_members
-- 						 left join stage.external_group_member egm on lower(egm.member_upn) = current_members.upn
-- 			where egm.external_group_member_id is null
-- 				and egm.user_group_id = __group_row.user_group_id;

			with deleted_users_completely_missing as materialized (
				delete
					from auth.user_group_member
						where user_group_member.member_id in
									(select ugm.member_id
									 from auth.user_group_member ugm
									 where ugm.group_id = __group_row.user_group_id
										 and ugm.mapping_id not in (select distinct user_group_mapping_id
																								from stage.external_group_member egm
																								where egm.user_group_id = __group_row.user_group_id))
						returning user_id, group_id, mapping_id)
			insert
			into __temp_external_group_sync
			select cr.group_id,
						 cr.mapping_id,
						 'deleted',
						 ui.user_id,
						 ui.username
			from deleted_users_completely_missing cr
						 inner join auth.user_info ui on cr.user_id = ui.user_id;
		end loop;


	return query
		select *
		from __temp_external_group_sync;

	drop table if exists __temp_delete_members;
	drop table if exists __temp_external_group_sync;
end;
$$;

create or replace function auth.search_user_groups(
    _user_id bigint,
    _search_text text default null,
    _is_active boolean default null,
    _is_external boolean default null,
    _is_system boolean default null,
    _page integer default 1,
    _page_size integer default 30,
    _tenant_id integer default 1
)
    returns TABLE(
        __user_group_id integer,
        __title text,
        __code text,
        __is_system boolean,
        __is_external boolean,
        __is_assignable boolean,
        __is_active boolean,
        __is_default boolean,
        __member_count bigint,
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
    perform auth.has_permission(_user_id, 'groups.get_group', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 30), 100);

    return query
        with filtered_groups as (
            select ug.user_group_id
                 , count(*) over () as total_items
            from auth.user_group ug
            where ug.tenant_id = _tenant_id
              and (_is_active is null or ug.is_active = _is_active)
              and (_is_external is null or ug.is_external = _is_external)
              and (_is_system is null or ug.is_system = _is_system)
              and (helpers.is_empty_string(__search_text)
                   or ug.nrm_search_data like '%' || __search_text || '%')
            order by ug.title
            offset ((_page - 1) * _page_size) limit _page_size
        ),
        member_counts as (
            select ugm.group_id, count(ugm.member_id) as member_count
            from auth.user_group_member ugm
            where ugm.group_id in (select user_group_id from filtered_groups)
            group by ugm.group_id
        )
        select ug.user_group_id
             , ug.title
             , ug.code
             , ug.is_system
             , ug.is_external
             , ug.is_assignable
             , ug.is_active
             , ug.is_default
             , coalesce(mc.member_count, 0)
             , fg.total_items
        from filtered_groups fg
                 inner join auth.user_group ug on fg.user_group_id = ug.user_group_id
                 left join member_counts mc on ug.user_group_id = mc.group_id;
end;
$$;

