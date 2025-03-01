/*
 GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=0&v=1&c=c&f=ANSI%20Shadow&t=STAGE%20FUNCS

 SUB GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=1&v=1&c=c&f=Banner3&t=permissions

 */
set
	search_path = public, const, ext, stage, helpers, internal, unsecure;

select *
from check_version('1.14', _component := 'keen_auth_permissions', _throw_err := true);

select *
from start_version_update('1.15',
													'Fix create_tenant and update_tenant + copy_perm_set',
													_component := 'keen_auth_permissions');

create
	or replace function unsecure.copy_perm_set(
	_created_by text, _user_id bigint, _source_perm_set_code text, _source_tenant_id int,
	_target_tenant_id int,
	_new_title text default null)
	returns setof auth.perm_set
	language plpgsql
as
$$
declare
	__created_perm_set   auth.perm_set;
	__source_perm_set    auth.perm_set;
	__source_tenant_code auth.tenant;
	__target_tenant_code auth.tenant;
begin

	select t.code
	from auth.tenant t
	where t.tenant_id = _source_tenant_id
	into __source_tenant_code;

	select t.code
	from auth.tenant t
	where t.tenant_id = _target_tenant_id
	into __target_tenant_code;

	select *
	from auth.perm_set
	where code = _source_perm_set_code
		and tenant_id = _source_tenant_id
	into __source_perm_set;

	if
		__source_perm_set is null then
		perform error.raise_52282(_source_perm_set_code);
	end if;

	insert into auth.perm_set(created_by, modified_by, tenant_id, title, is_system,
														is_assignable, code)
	values ( _created_by, _created_by, _target_tenant_id, coalesce(_new_title, __source_perm_set.title)
				 , __source_perm_set.is_system, __source_perm_set.is_assignable, helpers.get_code(_new_title))
	returning *
		into __created_perm_set;

-- copy assigned permissions

	insert into auth.perm_set_perm (created_by, perm_set_id, permission_id)
	select _created_by, __created_perm_set.perm_set_id, permission_id
	from auth.perm_set_perm
	where perm_set_id = __source_perm_set.perm_set_id;

	perform
		public.add_journal_msg_jsonb(_created_by, _user_id
			, format('Permission set(code: %s) from tenant (code: %s) copied to tenant: (code: %s) by user: %s'
																	 , _source_perm_set_code, __source_tenant_code, __target_tenant_code, _created_by)
			, 'perm_set'
			, __created_perm_set.perm_set_id
			, _data_object_code := __created_perm_set.code
			, _event_id := 50307
			, _tenant_id := _target_tenant_id);

	return query select * from auth.perm_set where perm_set_id = __created_perm_set.perm_set_id;
end;
$$;

drop function auth.create_tenant;
create
	or replace function auth.create_tenant(
	_created_by text
, _user_id bigint
, _title text
, _code text default null
, _is_removable bool default true
, _is_assignable bool default true
, _tenant_owner_id bigint default null)
	returns table
					(
						__tenant_id        integer,
						__uuid             uuid,
						__title            text,
						__code             text,
						__is_removable     boolean,
						__is_assignable    boolean,
						__access_type_code text,
						__is_default       boolean
					)
	language plpgsql
	rows 1
as
$$
declare
	__last_item auth.tenant;
	__tenant_owner_group_id  int;
	__tenant_member_group_id int;
begin
	perform
		auth.has_permission(_user_id, 'tenants.create_tenant');

	insert into auth.tenant (created_by, modified_by, title, code, is_removable, is_assignable)
	values (_created_by, _created_by, _title, coalesce(_code, helpers.get_code(_title)), _is_removable, _is_assignable)
	returning *
		into __last_item;

	perform
		add_journal_msg_jsonb(_created_by, _user_id
			, format('Tenant: (code: %s, title: %s) created by: %s'
														, __last_item.code, __last_item.title, _created_by)
			, 'tenant'
			, __last_item.tenant_id
			, _data_object_code := __last_item.code
			, _payload := jsonb_build_object(
						'title', _title
			, 'is_assignable', _is_assignable
			, 'is_removable', _is_removable
										)
			, _event_id := 50001
			, _tenant_id := 1);

	-- Create tenant admins
	select __user_group_id
	from unsecure.create_user_group(_created_by, _user_id, 'Tenant Admins'
		, true, true, false, true, _tenant_id := __last_item.tenant_id)
	into __tenant_owner_group_id;

	perform
		unsecure.copy_perm_set(_created_by, _user_id, 'tenant_admin', 1,
													 __last_item.tenant_id::int);
	perform
		unsecure.assign_permission(_created_by, _user_id
			, __tenant_owner_group_id, null, 'tenant_admin', _tenant_id := __last_item.tenant_id);

	-- Create tenant members
	select __user_group_id
	from unsecure.create_user_group(_created_by, _user_id, 'Tenant Members'
		, true, true, false, true, _tenant_id := __last_item.tenant_id)
	into __tenant_member_group_id;

	perform
		unsecure.copy_perm_set(_created_by, _user_id, 'tenant_member', 1,
													 __last_item.tenant_id::int);
	perform
		unsecure.assign_permission(_created_by, _user_id
			, __tenant_member_group_id, null, 'tenant_member', _tenant_id := __last_item.tenant_id);

	if
		(_tenant_owner_id is not null)
	then
		perform auth.create_owner(_created_by, _user_id, _tenant_owner_id, null, _tenant_id := __last_item.tenant_id);
	end if;

	return query
		select tenant_id
				 , uuid
				 , title
				 , code
				 , is_removable
				 , is_assignable
				 , access_type_code
				 , is_default
		from auth.tenant
		where tenant_id = __last_item.tenant_id;
end;
$$;

drop function auth.update_tenant;
create
	or replace function auth.update_tenant(
	_created_by text
, _user_id bigint
, _tenant_id int
, _title text
, _code text default null
, _is_removable bool default null
, _is_assignable bool default null
, _tenant_owner_id bigint default null)
	returns table
					(
						__tenant_id        integer,
						__uuid             uuid,
						__title            text,
						__code             text,
						__is_removable     boolean,
						__is_assignable    boolean,
						__access_type_code text,
						__is_default       boolean
					)
	language plpgsql
	rows 1
as
$$
begin
	perform
		auth.has_permission(_user_id, 'tenants.update_tenant');

	update auth.tenant
	set title         = _title
		, code          = coalesce(_code, code)
		, is_removable  = coalesce(_is_removable, is_removable)
		, is_assignable = coalesce(_is_assignable, is_assignable)
		, modified_by   = _created_by
		, modified      = now()
	where tenant_id = _tenant_id;

	perform
		add_journal_msg_jsonb(_created_by, _user_id
			, format('Tenant: (code: %s, title: %s) updated by: %s'
														, _code, _title, _created_by)
			, 'tenant'
			, _tenant_id
			, _data_object_code := _code
			, _payload := jsonb_build_object(
						'title', _title
			, 'is_assignable', _is_assignable
			, 'is_removable', _is_removable
										)
			, _event_id := 50002
			, _tenant_id := 1);

	if
		(_tenant_owner_id is not null)
	then
		perform auth.create_owner(_created_by, _user_id, _tenant_owner_id, null, _tenant_id := _tenant_id);
	end if;

	return query
		select tenant_id
				 , uuid
				 , title
				 , code
				 , is_removable
				 , is_assignable
				 , access_type_code
				 , is_default
		from auth.tenant
		where tenant_id = _tenant_id;
end;
$$;

/***
 *    ██████╗  ██████╗ ███████╗████████╗     ██████╗██████╗ ███████╗ █████╗ ████████╗███████╗
 *    ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝    ██╔════╝██╔══██╗██╔════╝██╔══██╗╚══██╔══╝██╔════╝
 *    ██████╔╝██║   ██║███████╗   ██║       ██║     ██████╔╝█████╗  ███████║   ██║   █████╗
 *    ██╔═══╝ ██║   ██║╚════██║   ██║       ██║     ██╔══██╗██╔══╝  ██╔══██║   ██║   ██╔══╝
 *    ██║     ╚██████╔╝███████║   ██║       ╚██████╗██║  ██║███████╗██║  ██║   ██║   ███████╗
 *    ╚═╝      ╚═════╝ ╚══════╝   ╚═╝        ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝
 *
 */

select *
from stop_version_update('1.15', _component := 'keen_auth_permissions');