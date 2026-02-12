/*
 * Auth Tenant Functions
 * =====================
 *
 * Tenant management: create/update/delete, user tenant access
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.get_tenants(_user_id bigint, _correlation_id text)
    returns TABLE(__created_at timestamp with time zone, __created_by text, __updated_at timestamp with time zone, __updated_by text, __tenant_id integer, __uuid text, __title text, __code text, __is_removable boolean, __is_assignable boolean)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.get_tenants');

	return query
		select created_at
				 , created_by
				 , updated_at
				 , updated_by
				 , tenant_id
				 , uuid::text
				 , title
				 , code
				 , is_removable
				 , is_assignable
		from auth.tenant t
		order by t.title;
end;
$$;

create or replace function auth.get_tenant_by_id(_tenant_id integer DEFAULT 1)
    returns TABLE(__created_at timestamp with time zone, __created_by text, __updated_at timestamp with time zone, __updated_by text, __tenant_id integer, __uuid text, __title text, __code text, __is_removable boolean, __is_assignable boolean)
    language sql
as
$$
select created_at
		 , created_by
		 , updated_at
		 , updated_by
		 , tenant_id
		 , uuid::text
		 , title
		 , code
		 , is_removable
		 , is_assignable
from auth.tenant t
where tenant_id = _tenant_id;
$$;

create or replace function auth.get_tenant_users(_requested_by text, _user_id bigint, _correlation_id text, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_id bigint, __username text, __display_name text, __user_groups text[])
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.get_users', _tenant_id);

	return query with tenant_users as (select ui.user_id
																					, ui.username
																					, ui.display_name
																					, ugs.user_group_id
																					, ugs.group_title
																					, ugs.group_code
																					, jsonb_build_object(variadic
																															 array ['user_group_id', ugs.user_group_id::text, 'code', ugs.group_code, 'title', ugs.group_title]) group_data
																		 from auth.user_group_members ugs
																						inner join auth.user_info ui on ugs.user_id = ui.user_id
																		 where ugs.tenant_id = _tenant_id
																		 order by ui.display_name)
							 select tu.user_id, tu.username, tu.display_name, array_agg(tu.group_data::text)
							 from tenant_users tu
							 group by tu.user_id, tu.username, tu.display_name;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function auth.get_tenant_groups(_requested_by text, _user_id bigint, _correlation_id text, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __group_code text, __group_title text, __is_external boolean, __is_assignable boolean, __is_active boolean, __members_count bigint)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.get_groups', _tenant_id);

	return query
		select ugs.user_group_id
				 , ugs.group_title
				 , ugs.group_code
				 , ugs.is_external
				 , ugs.is_assignable
				 , ugs.is_active
				 , count(ugs.user_id)
		from auth.user_group_members ugs
		where ugs.tenant_id = _tenant_id
		group by ugs.user_group_id, ugs.group_title, ugs.group_code, ugs.is_external, ugs.is_assignable, ugs.is_active
		order by ugs.group_title;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function auth.get_tenant_members(_requested_by text, _user_id bigint, _correlation_id text, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_id bigint, __user_display_name text, __user_code text, __user_uuid text, __user_tenant_groups text)
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.get_tenants', _tenant_id);

	return query
		select ugs.user_id
				 , ui.display_name as user_display_name
				 , ui.code         as user_code
				 , ui.uuid::text   as user_uuid
				 , array_to_json(array_agg(distinct
																	 jsonb_build_object('user_group_id', ugs.user_group_id, 'group_title',
																											ugs.group_title,
																											'group_code', ugs.group_code))) ::text
		from auth.user_group_members ugs
					 inner join auth.user_info ui on ugs.user_id = ui.user_id
		where ugs.tenant_id = _tenant_id
		group by ugs.user_id, ui.display_name, ui.code, ui.uuid
		order by ui.display_name;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function auth.delete_tenant(_deleted_by text, _user_id bigint, _correlation_id text, _tenant_uuid uuid)
    returns TABLE(__tenant_id integer, __uuid uuid, __code text)
    rows 1
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'tenants.delete_tenant');

    return query
        select *
        from auth.tenant t
           , lateral unsecure.delete_tenant(_deleted_by, _user_id, _correlation_id, t.tenant_id)
        where t.uuid = _tenant_uuid;
end;
$$;

create or replace function auth.delete_tenant_by_uuid(_deleted_by text, _user_id bigint, _correlation_id text, _tenant_uuid uuid)
    returns TABLE(__tenant_id integer, __uuid uuid, __code text)
    rows 1
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'tenants.delete_tenant');

    return query
        select *
        from auth.tenant t
           , lateral unsecure.delete_tenant(_deleted_by, _user_id, _correlation_id, t.tenant_id)
        where t.uuid = _tenant_uuid;
end;
$$;

create or replace function auth.get_user_available_tenants(_user_id bigint, _correlation_id text, _target_user_id bigint)
    returns TABLE(__tenant_id integer, __tenant_uuid text, __tenant_code text, __tenant_title text, __tenant_is_default boolean)
    language plpgsql
as
$$
declare
    __necessary_permission_code text := 'users.get_available_tenants';
begin

    if _user_id <> _target_user_id and not auth.has_permission(_user_id, _correlation_id, __necessary_permission_code)
    then
        perform auth.throw_no_permission(_user_id, __necessary_permission_code);
    end if;

    return query
        with member_of_tenants as (
            select tenant_id
                 , group_id
            from auth.user_group_member ugm
                     inner join auth.user_group ug on ug.user_group_id = ugm.group_id
            where ugm.user_id = _target_user_id)
        select distinct mt.tenant_id
             , t.uuid::text
             , t.code
             , t.title
             , t.is_default
        from member_of_tenants mt
                 inner join auth.tenant t on mt.tenant_id = t.tenant_id
        order by t.title;
end;
$$;

create or replace function auth.create_user_tenant_preferences(_created_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _update_data text, _tenant_id integer DEFAULT 1)
    returns TABLE(__created_at timestamp with time zone, __created_by character varying)
    rows 1
    language plpgsql
as
$$
begin
    if _user_id <> _target_user_id
    then
        perform auth.has_permission(_user_id, _correlation_id, 'users.create_user_tenant_preferences', _tenant_id);
    end if;

    return query
        insert into auth.user_tenant_preference (created_by, updated_by, user_id, tenant_id, user_preferences)
            values (_created_by, _created_by, _user_id, _tenant_id, _update_data::jsonb)
            returning updated_at
                , updated_by;
end;
$$;

create or replace function auth.update_user_tenant_preferences(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _update_data text, _should_overwrite_data boolean DEFAULT false, _tenant_id integer DEFAULT 1)
    returns TABLE(__updated_at timestamp with time zone, __updated_by character varying)
    rows 1
    language plpgsql
as
$$
declare
    __update_data jsonb := _update_data::jsonb;
begin

    if _user_id <> _target_user_id
    then
        perform auth.has_permission(_user_id, _correlation_id, 'users.update_user_tenant_preferences', _tenant_id);
    end if;

    return query
        update auth.user_tenant_preference
            set updated_at = now()
                , updated_by = _updated_by
                , user_preferences =
                    case when _should_overwrite_data then __update_data else user_preferences || __update_data end
            where user_id = _target_user_id and tenant_id = _tenant_id
            returning updated_at
                , updated_by;
end;
$$;

create or replace function auth.get_user_last_selected_tenant(_user_id bigint, _correlation_id text, _target_user_id bigint)
    returns TABLE(__tenant_id integer, __tenant_uuid text, __tenant_code text, __tenant_title text)
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
        select t.tenant_id
             , t.uuid::text
             , t.code
             , t.title
        from auth.user_info ui
                 inner join auth.tenant t on ui.last_selected_tenant_id = t.tenant_id
        where ui.user_id = _target_user_id
          and ui.last_selected_tenant_id is not null;
end;
$$;

create or replace function auth.update_user_last_selected_tenant(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_uuid text)
    returns TABLE(__used_id bigint, __tenant_id integer)
    rows 1
    language plpgsql
as
$$
declare
    __tenant_id int;
begin
    if _user_id <> _target_user_id
    then
        perform auth.has_permission(_user_id, _correlation_id, 'users.update_last_selected_tenant');
    end if;

    select t.tenant_id
    from auth.tenant t
             inner join auth.user_group_members ugms on t.tenant_id = ugms.tenant_id
    where t.uuid = _tenant_uuid::uuid
      and ugms.user_id = _user_id
    into __tenant_id;

    if __tenant_id is null
    then
        perform error.raise_52108(_tenant_uuid, _updated_by);
    end if;

    return query
        update auth.user_info
            set updated_at = now()
                , updated_by = _updated_by
                , last_selected_tenant_id = __tenant_id
            where user_id = _target_user_id
            returning user_id, last_selected_tenant_id;


    if _user_id <> _target_user_id and _user_id <> 1
    then
        perform create_journal_message('system', _user_id, _correlation_id
                , 10002  -- user_updated
                , 'user', _target_user_id
                , jsonb_build_object('username', _target_user_id::text, 'tenant_id', __tenant_id
                    , 'action', 'last_selected_tenant_updated')
                , 1);
    end if;
end;
$$;

create or replace function auth.get_all_tenants()
    returns TABLE(__tenant_id integer, __tenant_uuid text, __tenant_code text, __tenant_title text)
    stable
    language sql
as
$$
select tenant_id
     , uuid::text
     , code
     , title
from auth.tenant
order by title
$$;

create or replace function auth.create_tenant(_created_by text, _user_id bigint, _correlation_id text, _title text, _code text DEFAULT NULL::text, _is_removable boolean DEFAULT true, _is_assignable boolean DEFAULT true, _tenant_owner_id bigint DEFAULT NULL::bigint)
    returns TABLE(__tenant_id integer, __uuid uuid, __title text, __code text, __is_removable boolean, __is_assignable boolean, __access_type_code text, __is_default boolean)
    rows 1
    language plpgsql
as
$$
declare
	__last_item auth.tenant;
	__tenant_owner_group_id
							int;
	__tenant_member_group_id
							int;
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.create_tenant');

	insert into auth.tenant (created_by, updated_by, title, code, is_removable, is_assignable)
	values (_created_by, _created_by, _title, coalesce(_code, helpers.get_code(_title)), _is_removable, _is_assignable)
	returning *
		into __last_item;

	perform create_journal_message(_created_by, _user_id, _correlation_id
			, 11001  -- tenant_created
			, 'tenant', __last_item.tenant_id
			, jsonb_build_object('tenant_title', __last_item.title, 'tenant_code', __last_item.code
				, 'is_assignable', _is_assignable, 'is_removable', _is_removable)
			, 1);

	-- Create tenant admins
	select __user_group_id
	from unsecure.create_user_group(_created_by, _user_id, _correlation_id, 'Tenant Admins'
		, true, true, false, true, _tenant_id := __last_item.tenant_id)
	into __tenant_owner_group_id;

	perform
		unsecure.copy_perm_set(_created_by, _user_id, _correlation_id, 'tenant_admin', 1,
													 __last_item.tenant_id::int);
	perform
		unsecure.assign_permission(_created_by, _user_id, _correlation_id
			, __tenant_owner_group_id, null, 'tenant_admin', _tenant_id := __last_item.tenant_id);

	-- Create tenant members
	select __user_group_id
	from unsecure.create_user_group(_created_by, _user_id, _correlation_id, 'Tenant Members'
		, true, true, false, true, _tenant_id := __last_item.tenant_id)
	into __tenant_member_group_id;

	perform
		unsecure.copy_perm_set(_created_by, _user_id, _correlation_id, 'tenant_member', 1,
													 __last_item.tenant_id::int);
	perform
		unsecure.assign_permission(_created_by, _user_id, _correlation_id
			, __tenant_member_group_id, null, 'tenant_member', _tenant_id := __last_item.tenant_id);

	if
		(_tenant_owner_id is not null)
	then
		perform auth.create_owner(_created_by, _user_id, _correlation_id, _tenant_owner_id, null, _tenant_id := __last_item.tenant_id);
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

create or replace function auth.update_tenant(_created_by text, _user_id bigint, _correlation_id text, _tenant_id integer, _title text, _code text DEFAULT NULL::text, _is_removable boolean DEFAULT NULL::boolean, _is_assignable boolean DEFAULT NULL::boolean, _tenant_owner_id bigint DEFAULT NULL::bigint)
    returns TABLE(__tenant_id integer, __uuid uuid, __title text, __code text, __is_removable boolean, __is_assignable boolean, __access_type_code text, __is_default boolean)
    rows 1
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'tenants.update_tenant');

	update auth.tenant
	set title         = _title
		, code          = coalesce(_code, code)
		, is_removable  = coalesce(_is_removable, is_removable)
		, is_assignable = coalesce(_is_assignable, is_assignable)
		, updated_by    = _created_by
		, updated_at    = now()
	where tenant_id = _tenant_id;

	perform create_journal_message(_created_by, _user_id, _correlation_id
			, 11002  -- tenant_updated
			, 'tenant', _tenant_id
			, jsonb_build_object('tenant_title', _title, 'tenant_code', _code
				, 'is_assignable', _is_assignable, 'is_removable', _is_removable)
			, 1);

	if
		(_tenant_owner_id is not null)
	then
		perform auth.create_owner(_created_by, _user_id, _correlation_id, _tenant_owner_id, null, _tenant_id := _tenant_id);
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

create or replace function auth.search_tenants(
    _user_id bigint,
    _correlation_id text,
    _search_text text default null,
    _page integer default 1,
    _page_size integer default 30
)
    returns TABLE(
        __tenant_id integer,
        __uuid text,
        __title text,
        __code text,
        __is_removable boolean,
        __is_assignable boolean,
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
    perform auth.has_permission(_user_id, _correlation_id, 'tenants.read_tenants');

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 30), 100);

    return query
        with filtered_tenants as (
            select t.tenant_id
                 , count(*) over () as total_items
            from auth.tenant t
            where (helpers.is_empty_string(__search_text)
                   or t.nrm_search_data like '%' || __search_text || '%')
            order by t.title
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select t.tenant_id
             , t.uuid::text
             , t.title
             , t.code
             , t.is_removable
             , t.is_assignable
             , ft.total_items
        from filtered_tenants ft
                 inner join auth.tenant t on ft.tenant_id = t.tenant_id;
end;
$$;

