/*
 * Unsecure Functions
 * ==================
 *
 * Internal functions without permission checks - for trusted contexts only
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function unsecure.clear_permission_cache(_deleted_by text, _target_user_id bigint, _tenant_id integer DEFAULT NULL) returns void
    language sql
as
$$
-- Clear permission cache for user
-- If _tenant_id is NULL, clears cache for ALL tenants (used when user is locked/disabled)
-- If _tenant_id is specified, clears only that tenant's cache
delete
from auth.user_permission_cache
where user_id = _target_user_id
  and (_tenant_id is null or tenant_id = _tenant_id);
$$;

-- Helper function to invalidate cache for all members of a group
-- Uses soft invalidation (UPDATE expiration_date) instead of DELETE for better performance
create or replace function unsecure.invalidate_group_members_permission_cache(_updated_by text, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    update auth.user_permission_cache
    set expiration_date = now(),
        updated_by = _updated_by,
        updated_at = now()
    where tenant_id = _tenant_id
      and user_id in (
          select user_id
          from auth.user_group_member
          where user_group_id = _user_group_id
      );
end;
$$;

-- Helper function to invalidate cache for all users with a specific perm_set assigned
-- Uses soft invalidation (UPDATE expiration_date) instead of DELETE for better performance:
-- - UPDATE is ~5-10x faster than DELETE (no index rebalancing)
-- - Next has_permission call will recalculate immediately (checks expiration_date > now())
-- - No transaction blocking from mass row deletions
create or replace function unsecure.invalidate_perm_set_users_permission_cache(_updated_by text, _perm_set_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    -- Soft invalidate cache for users who have this perm_set directly assigned
    update auth.user_permission_cache
    set expiration_date = now(),
        updated_by = _updated_by,
        updated_at = now()
    where tenant_id = _tenant_id
      and user_id in (
          select user_id
          from auth.permission_assignment
          where perm_set_id = _perm_set_id
            and user_id is not null
      );

    -- Soft invalidate cache for users who are members of groups that have this perm_set assigned
    update auth.user_permission_cache
    set expiration_date = now(),
        updated_by = _updated_by,
        updated_at = now()
    where tenant_id = _tenant_id
      and user_id in (
          select ugm.user_id
          from auth.permission_assignment pa
          inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id
          where pa.perm_set_id = _perm_set_id
      );
end;
$$;

-- Helper function to invalidate cache for a list of user IDs
-- Used by triggers that need to invalidate multiple users at once (e.g. group delete, provider delete)
create or replace function unsecure.invalidate_users_permission_cache(_updated_by text, _user_ids bigint[], _tenant_id integer DEFAULT NULL) returns void
    language plpgsql
as
$$
begin
    update auth.user_permission_cache
    set expiration_date = now(),
        updated_by = _updated_by,
        updated_at = now()
    where user_id = any(_user_ids)
      and (_tenant_id is null or tenant_id = _tenant_id);
end;
$$;

-- Helper function to invalidate cache for all users affected by a permission change
-- Finds users via: direct assignment, perm_set membership, and group membership
create or replace function unsecure.invalidate_permission_users_cache(_updated_by text, _permission_id integer) returns void
    language plpgsql
as
$$
begin
    update auth.user_permission_cache
    set expiration_date = now(),
        updated_by = _updated_by,
        updated_at = now()
    where user_id in (
        -- Users with this permission directly assigned
        select pa.user_id
        from auth.permission_assignment pa
        where pa.permission_id = _permission_id
          and pa.user_id is not null

        union

        -- Users in groups with this permission directly assigned
        select ugm.user_id
        from auth.permission_assignment pa
        inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id
        where pa.permission_id = _permission_id

        union

        -- Users with this permission via perm_set (direct assignment)
        select pa.user_id
        from auth.perm_set_perm psp
        inner join auth.permission_assignment pa on pa.perm_set_id = psp.perm_set_id
        where psp.permission_id = _permission_id
          and pa.user_id is not null

        union

        -- Users with this permission via perm_set (group assignment)
        select ugm.user_id
        from auth.perm_set_perm psp
        inner join auth.permission_assignment pa on pa.perm_set_id = psp.perm_set_id
        inner join auth.user_group_member ugm on ugm.user_group_id = pa.user_group_id
        where psp.permission_id = _permission_id
    );
end;
$$;

-- Send a notification via pg_notify on the 'permission_changes' channel
-- Called from trigger functions and unsecure.* functions to notify backends of permission-relevant changes
create or replace function unsecure.notify_permission_change(
    _event       text,
    _tenant_id   integer,
    _target_type text,
    _target_id   bigint,
    _detail      jsonb DEFAULT NULL
) returns void
    language plpgsql
as
$$
declare
    _payload jsonb;
begin
    _payload := jsonb_build_object(
        'event', _event,
        'tenant_id', _tenant_id,
        'target_type', _target_type,
        'target_id', _target_id,
        'at', now()
    );

    if _detail is not null then
        _payload := _payload || jsonb_build_object('detail', _detail);
    end if;

    perform pg_notify('permission_changes', _payload::text);
end;
$$;

-- Helper function to verify owner or permission for owner management operations
create or replace function unsecure.verify_owner_or_permission(_user_id bigint, _correlation_id text, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    if not auth.is_owner(_user_id, _correlation_id, _user_group_id, _tenant_id)
        and not auth.is_owner(_user_id, _correlation_id, null, _tenant_id)
    then
        if _user_group_id is not null then
            perform auth.has_permission(_user_id, _correlation_id
                , 'tenants.assign_group_owner', _tenant_id);
        else
            perform auth.has_permission(_user_id, _correlation_id
                , 'tenants.assign_owner', _tenant_id);
        end if;
    end if;
end;
$$;

create or replace function unsecure.create_primary_tenant() returns SETOF auth.tenant
    rows 1
    language sql
as
$$
insert into auth.tenant(created_by, updated_by, title, code, is_removable, is_assignable)
values ('initial_script', 'initial_script', 'Primary', 'primary', false, true)
returning *;
$$;

create or replace function unsecure.create_user_system() returns SETOF auth.user_info
    rows 1
    language sql
as
$$
insert into auth.user_info( created_by, updated_by, user_type_code, can_login, email, display_name, username
													, original_username)
values ('initial_script', 'initial_script', 'system', false, 'system', 'System', 'system', 'system')
returning *;

$$;

create or replace function unsecure.delete_user_by_username_as_system(_username text) returns auth.user_info
    language sql
as
$$
delete
from auth.user_info
where lower(username) = lower(_username)
returning *;

$$;

create or replace function unsecure.delete_user_by_id(_deleted_by text, _user_id bigint, _correlation_id text, _target_user_id bigint)
    returns TABLE(__user_id bigint, __username text)
    language sql
as
$$

delete
from auth.user_info
where user_id = _target_user_id
returning user_id, username;

$$;

create or replace function unsecure.create_user_event(_created_by text, _user_id bigint, _correlation_id text, _event_type_code text, _target_user_id bigint, _ip_address text DEFAULT NULL::text, _user_agent text DEFAULT NULL::text, _origin text DEFAULT NULL::text, _event_data jsonb DEFAULT NULL::jsonb, _target_user_oid text DEFAULT NULL::text, _target_username text DEFAULT NULL::text)
    returns TABLE(__user_event_id bigint)
    language plpgsql
as
$$
declare
	__requester_username text;
begin
	--     perform auth.has_permission( _user_id, 'authentication.create_user_event');

	if
			_user_id is not null and (__requester_username is null or __requester_username = '') then
		select username
		from auth.user_info ui
		where ui.user_id = _user_id
		into __requester_username;
	end if;

	if
		_target_user_id is not null and _target_username is null then
		select username
		from auth.user_info ui
		where ui.user_id = _target_user_id
		into _target_username;
	end if;

	return query insert into auth.user_event (created_by,
																						correlation_id,
																						event_type_code,
																						requester_user_id,
																						requester_username,
																						target_user_id,
																						target_user_oid,
																						target_username,
																						ip_address,
																						user_agent,
																						origin,
																						event_data)
		values ( _created_by, _correlation_id, _event_type_code, _user_id, __requester_username, _target_user_id, _target_user_oid
					 , _target_username, _ip_address, _user_agent, _origin, _event_data)
		returning user_event_id;
end;
$$;

create or replace function unsecure.expire_tokens(_created_by text) returns void
    language plpgsql
as
$$
declare
    __expired_count bigint;
begin
    update auth.token
    set updated_at       = now()
      , updated_by       = _created_by
      , token_state_code = 'expired'
    where token_state_code = 'valid'
      and expires_at < now();

    get diagnostics __expired_count = row_count;

    if __expired_count > 0 then
        perform create_journal_message_for_entity(_created_by, 1, null
            , 15003  -- token_expired
            , 'token', 0
            , jsonb_build_object('expired_count', __expired_count, 'action', 'batch_expiration')
            , 1);
    end if;
end;
$$;

create or replace function unsecure.create_user_group(_created_by text, _user_id bigint, _correlation_id text, _title text, _is_assignable boolean DEFAULT true, _is_active boolean DEFAULT true, _is_external boolean DEFAULT false, _is_system boolean DEFAULT false, _is_default boolean DEFAULT false, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer)
    rows 1
    language plpgsql
as
$$
declare
	__last_id int;
begin

	insert into auth.user_group ( created_by, updated_by, tenant_id, title, is_default, is_system, is_assignable
															, is_active, is_external)
	values ( _created_by, _created_by, _tenant_id, _title, _is_default, _is_system, _is_assignable, _is_active
				 , _is_external)
	returning user_group_id
		into __last_id;

	return query
		select __last_id;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 13001  -- group_created
			, 'group', __last_id
			, jsonb_build_object('group_title', _title, 'tenant_title', _tenant_id::text
				, 'is_default', _is_default, 'is_system', _is_system
				, 'is_assignable', _is_assignable, 'is_active', _is_active)
			, _tenant_id);

end ;
$$;

create or replace function unsecure.create_user_group_as_system(_title text, _is_system boolean DEFAULT false, _is_assignable boolean DEFAULT true, _is_default boolean DEFAULT false, _tenant_id integer DEFAULT 1) returns SETOF auth.user_group
    rows 1
    language sql
as
$$
select ug.*
from unsecure.create_user_group('system', 1, null, _title, _is_assignable, true, false, _is_system, _is_default, _tenant_id) g
			 inner join auth.user_group ug on ug.user_group_id = g.__user_group_id;

$$;

create or replace function unsecure.create_user_group_member_as_system(_user_name text, _group_title text, _tenant_id integer DEFAULT 1) returns SETOF auth.user_group_member
    language plpgsql
as
$$
declare
	__user_id       bigint;
	__user_group_id int;
begin
	select ui.user_id
	from auth.user_info ui
	where ui.username = _user_name
	into __user_id;

	select user_group_id
	from auth.user_group ug
	where lower(ug.title) = lower(_group_title)
	into __user_group_id;

	return query
		select ugm.*
		from unsecure.create_user_group_member('system', 1, null, __user_group_id, __user_id, _tenant_id) r
					 inner join auth.user_group_member ugm on ugm.member_id = r.__user_group_member_id;
end;
$$;

create or replace function unsecure.get_user_group_by_id(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_id integer, __tenant_id integer, __title text, __code text, __is_system boolean, __is_external boolean, __is_assignable boolean, __is_active boolean, __is_default boolean)
    language plpgsql
as
$$
begin
	return query select user_group_id
										, tenant_id
										, title
										, code
										, is_system
										, is_external
										, is_assignable
										, is_active
										, is_default
							 from auth.user_group
							 where user_group_id = _user_group_id;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end
$$;

create or replace function unsecure.get_effective_group_permissions(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__full_code text, __permission_title text, __perm_set_title text, __perm_set_code text, __perm_set_id integer, __assignment_id bigint)
    language plpgsql
as
$$
begin

	return query
--         Get all assigned permissions from permsets
		select distinct ep.permission_code::text as full_code
									, ep.permission_title
									, ep.perm_set_title
									, ep.perm_set_code
									, ep.perm_set_id
									, pa.assignment_id
		from auth.permission_assignment pa
					 inner join auth.effective_permissions ep
											on pa.perm_set_id = ep.perm_set_id and pa.user_group_id = _user_group_id
		where ep.perm_set_is_assignable = true
			and ep.permission_is_assignable = true
		union
--         Get permissions that are directly assigned
		select distinct sp.full_code::text
									, sp.title
									, null
									, null
									, null::integer
									, pa.assignment_id
		from auth.permission_assignment pa
					 inner join auth.permission p on pa.permission_id = p.permission_id and _user_group_id = pa.user_group_id
					 inner join auth.permission sp
											on sp.node_path <@ p.node_path and sp.is_assignable = true;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function unsecure.get_assigned_group_permissions(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__permissions jsonb, __perm_set_title text, __perm_set_id integer, __perm_set_code text, __assignment_id bigint)
    language plpgsql
as
$$
begin

	return query
		with permission_ids as (select distinct coalesce(pa.permission_id, psp.permission_id) as permission_id
																					, ps.title                                      as perm_set_title
																					, pa.perm_set_id
																					, ps.code
																					, pa.assignment_id
														from auth.permission_assignment pa
																	 left join auth.perm_set ps on ps.perm_set_id = pa.perm_set_id
																	 left join auth.perm_set_perm psp on ps.perm_set_id = psp.perm_set_id
														where user_group_id = _user_group_id)
		select jsonb_agg(jsonb_build_object('code', p.full_code, 'title', p.title, 'id',
																				p.permission_id)) as permissions
				 , pids.perm_set_title
				 , pids.perm_set_id
				 , pids.code                                      as perm_set_code
				 , pids.assignment_id
		from permission_ids pids
					 inner join auth.permission p on pids.permission_id = p.permission_id
		group by pids.assignment_id, pids.perm_set_title, pids.perm_set_id, pids.code
		order by perm_set_title nulls last;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)

end;
$$;

create or replace function unsecure.assign_permission(_created_by text, _user_id bigint, _correlation_id text, _user_group_id integer DEFAULT NULL::integer, _target_user_id bigint DEFAULT NULL::bigint, _perm_set_code text DEFAULT NULL::text, _perm_code text DEFAULT NULL::text, _tenant_id integer DEFAULT 1) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
declare
	__last_id               bigint;
	__perm_set_id           int;
	__perm_set_assignable   bool;
	__permission_id         int;
	__permission_assignable bool;
begin

	if _user_group_id is null and _target_user_id is null then
		perform error.raise_52272();
	end if;

	-- Enforce mutual exclusivity: cannot specify both group and user
	if _user_group_id is not null and _target_user_id is not null then
		raise exception 'Cannot specify both group and user for permission assignment'
			using errcode = '22023';  -- invalid_parameter_value
	end if;

	if
		_perm_set_code is null and _perm_code is null then
		perform error.raise_52273();
	end if;

	if _user_group_id is not null and not exists(select
																							 from auth.user_group ug
																							 where ug.user_group_id = _user_group_id) then
		perform error.raise_52171(_user_group_id);
	end if;

	if _target_user_id is not null and not exists(select
																								from auth.user_info ui
																								where ui.user_id = _target_user_id) then
		perform error.raise_52103(_target_user_id);
	end if;

	if _perm_set_code is not null then
		select ps.perm_set_id, ps.is_assignable
		from auth.perm_set ps
		where ps.tenant_id = _tenant_id
		and ps.code = _perm_set_code
		into __perm_set_id, __perm_set_assignable;

		if __perm_set_id is null then
			perform error.raise_52282(_perm_set_code);
		else
			if not __perm_set_assignable then
				perform error.raise_52283(_perm_code);
			end if;
		end if;
	end if;

	if _perm_code is not null then
		select p.permission_id, p.is_assignable
		from auth.permission p
		where p.full_code = _perm_code::ext.ltree
		into __permission_id, __permission_assignable;

		if __permission_id is null then
			perform error.raise_52180(_perm_code);
		else
			if not __permission_assignable then
				perform error.raise_52181(_perm_code);
			end if;
		end if;
	end if;

	insert into auth.permission_assignment (created_by, tenant_id, user_group_id, user_id, perm_set_id, permission_id)
	values (_created_by, _tenant_id, _user_group_id, _target_user_id, __perm_set_id, __permission_id)
	returning assignment_id
		into __last_id;

	return query
		select *
		from auth.permission_assignment
		where assignment_id = __last_id;

	if _user_group_id is not null then
		perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12010  -- permission_assigned
			, 'group', _user_group_id
			, jsonb_build_object('permission_code', coalesce(_perm_set_code, _perm_code)
				, 'target_type', 'group', 'target_name', _user_group_id::text
				, 'assignment_id', __last_id, 'perm_set_code', _perm_set_code)
			, _tenant_id);

		-- Invalidate permission cache for all members of the group
		perform unsecure.invalidate_group_members_permission_cache(_created_by, _user_group_id, _tenant_id);
	else
		perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12010  -- permission_assigned
			, 'user', _target_user_id
			, jsonb_build_object('permission_code', coalesce(_perm_set_code, _perm_code)
				, 'target_type', 'user', 'target_name', _target_user_id::text
				, 'assignment_id', __last_id, 'perm_set_code', _perm_set_code)
			, _tenant_id);

		-- Invalidate permission cache for the target user
		perform unsecure.clear_permission_cache(_created_by, _target_user_id, _tenant_id);
	end if;
end;
$$;

create or replace function unsecure.unassign_permission(_deleted_by text, _user_id bigint, _correlation_id text, _assignment_id bigint, _tenant_id integer DEFAULT 1) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
declare
	__user_group_id  int;
	__target_user_id int;
begin

	select user_group_id, user_id
	from auth.permission_assignment pa
	where pa.assignment_id = _assignment_id
	into __user_group_id, __target_user_id;

	return query
		delete
			from auth.permission_assignment
				where assignment_id = _assignment_id
				returning *;

	if __user_group_id is not null then
		perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 12011  -- permission_revoked
			, 'group', __user_group_id
			, jsonb_build_object('target_type', 'group', 'target_name', __user_group_id::text
				, 'assignment_id', _assignment_id)
			, _tenant_id);

		-- Invalidate permission cache for all members of the group
		perform unsecure.invalidate_group_members_permission_cache(_deleted_by, __user_group_id, _tenant_id);
	else
		perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 12011  -- permission_revoked
			, 'user', __target_user_id
			, jsonb_build_object('target_type', 'user', 'target_name', __target_user_id::text
				, 'assignment_id', _assignment_id)
			, _tenant_id);

		-- Invalidate permission cache for the target user
		perform unsecure.clear_permission_cache(_deleted_by, __target_user_id, _tenant_id);
	end if;
end;

$$;

create or replace function unsecure.set_permission_as_assignable(_updated_by text, _user_id bigint, _correlation_id text, _permission_id integer DEFAULT NULL::integer, _permission_full_code text DEFAULT NULL::text, _is_assignable boolean DEFAULT true) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
declare
	__permission_id        int;
	__permission_full_code text;
begin

	if
		_permission_id is null and _permission_full_code is null then
		perform error.raise_52274();
	end if;

	__permission_id := _permission_id;

	if
		__permission_id is null then
		select permission_id
		from auth.permission
		where full_code = _permission_full_code
		into __permission_id;

		if
			__permission_id is null then
			perform error.raise_52275(_permission_full_code);
		end if;
	end if;

	update auth.permission
	set updated_at    = now()
		, updated_by    = _updated_by
		, is_assignable = _is_assignable
	where permission_id = __permission_id
	returning full_code
		into __permission_full_code;

	-- Invalidate cache for all users who have this permission (directly or via perm_sets/groups)
	perform unsecure.invalidate_permission_users_cache(_updated_by, __permission_id);

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 12002  -- permission_updated
			, 'permission', __permission_id
			, jsonb_build_object('permission_code', __permission_full_code, 'is_assignable', _is_assignable)
			, 1);
end;
$$;

create or replace function unsecure.assign_permission_as_system(_user_group_id integer, _target_user_id bigint, _perm_set_code text, _perm_code text DEFAULT NULL::text, _tenant_id integer DEFAULT 1) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
begin
	return query
		select *
		from unsecure.assign_permission('system', 1, null, _user_group_id, _target_user_id, _perm_set_code,
																		_perm_code, _tenant_id);
end;

$$;

create or replace function unsecure.update_permission_full_title(_perm_path ext.ltree) returns SETOF auth.permission
    rows 1
    language sql
as
$$
update auth.permission p
set full_title =
			-- 			case
-- 				when _perm_path = '1'::ext.ltree then 'System'
-- 				else
			(select array_to_string(
											ARRAY(select p_n2.title
														from auth.permission as p_n2
														where p_n2.node_path @> p_n.node_path
															and p_n2.permission_id <> 1
														order by p_n2.node_path),
											' > ')
			 from auth.permission as p_n
			 where p_n.permission_id = p.permission_id)
-- 				end
where p.node_path <@ _perm_path
returning *;
$$;

create or replace function unsecure.update_permission_full_code(_perm_path ext.ltree) returns SETOF auth.permission
    rows 1
    language sql
as
$$
update auth.permission p
set full_code = (select ext.text2ltree(array_to_string(
				ARRAY(select coalesce(p_n2.code, helpers.get_code(p_n2.title, '_'))
							from auth.permission as p_n2
							where p_n2.node_path @> p_n.node_path
							order by p_n2.node_path),
				'.'))
								 from auth.permission as p_n
								 where p_n.permission_id = p.permission_id)
where p.node_path <@ _perm_path
returning *;
$$;

create or replace function unsecure.compute_short_code(_permission_id integer) returns text
    stable
    language plpgsql
as
$$
declare
    __ancestors  ltree;
    __result     text := '';
    __depth      integer;
    __max_depth  integer;
    __ancestor   record;
    __ordinal    integer;
begin
    -- Get the node_path for this permission
    select node_path
    from auth.permission
    where permission_id = _permission_id
    into __ancestors;

    if __ancestors is null then
        return null;
    end if;

    __max_depth := ext.nlevel(__ancestors);

    for __depth in 1..__max_depth loop
        -- Get the permission_id at this depth of the path
        select p.permission_id, p.node_path
        from auth.permission p
        where p.node_path = ext.subltree(__ancestors, 0, __depth)
        into __ancestor;

        -- Count siblings with permission_id <= this one at the same depth/parent
        if __depth = 1 then
            -- Root level: count root permissions with id <= this one
            select count(*)
            from auth.permission p2
            where ext.nlevel(p2.node_path) = 1
              and p2.permission_id <= __ancestor.permission_id
            into __ordinal;
        else
            -- Child level: count siblings under same parent with id <= this one
            select count(*)
            from auth.permission p2
            where p2.node_path <@ ext.subltree(__ancestors, 0, __depth - 1)
              and ext.nlevel(p2.node_path) = __depth
              and p2.permission_id <= __ancestor.permission_id
            into __ordinal;
        end if;

        if __result = '' then
            __result := lpad(__ordinal::text, 2, '0');
        else
            __result := __result || '.' || lpad(__ordinal::text, 2, '0');
        end if;
    end loop;

    return __result;
end;
$$;

create or replace function unsecure.update_permission_short_code(_perm_path ext.ltree) returns SETOF auth.permission
    rows 1
    language sql
as
$$
update auth.permission p
set short_code = unsecure.compute_short_code(p.permission_id)
where p.node_path <@ _perm_path
returning *;
$$;

create or replace function unsecure.create_permission(_created_by text, _user_id bigint, _correlation_id text, _title text, _parent_full_code text DEFAULT NULL::text, _is_assignable boolean DEFAULT true, _short_code text DEFAULT NULL::text, _source text DEFAULT NULL::text) returns SETOF auth.permission
    rows 1
    language plpgsql
as
$$
declare
	__last_id     int;
	__p           ext.ltree;
	__parent_id   int;
	__parent_path text;
	__full_code   ext.ltree;
begin

	insert into auth.permission(created_by, updated_by, title, is_assignable, code, source)
	values (_created_by, _created_by, _title, _is_assignable, helpers.get_code(_title, '_'), _source)
	returning permission_id
		into __last_id;

	if helpers.is_empty_string(_parent_full_code) then
		begin
			__p := ext.text2ltree(__last_id::text);

			update auth.permission
			set node_path = __p
			where permission_id = __last_id;
		end;
	else
		begin
			select p.permission_id, node_path::text
			from auth.permission p
			where p.full_code = ext.text2ltree(_parent_full_code)
			into __parent_id, __parent_path;

			if __parent_id is null then
				perform error.raise_52179(_parent_full_code);
			end if;

			__p := ext.text2ltree(__parent_path || '.' || __last_id::text);

			update auth.permission
			set node_path = __p
			where permission_id = __last_id;

			update auth.permission
			set has_children = true
			where permission_id = __parent_id;
		end;

	end if;

	perform unsecure.update_permission_full_title(__p);
	select full_code
	from unsecure.update_permission_full_code(__p)
	into __full_code;

	if helpers.is_not_empty_string(_short_code) then
		update auth.permission set short_code = _short_code where permission_id = __last_id;
	else
		perform unsecure.update_permission_short_code(__p);
	end if;

	return query
		select *
		from auth.permission
		where permission_id = __last_id;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12001  -- permission_created
			, 'permission', __last_id
			, jsonb_build_object('permission_code', __full_code::text, 'title', _title)
			, 1);
end;
$$;

create or replace function unsecure.create_permission_as_system(_title text, _parent_code text DEFAULT ''::text, _is_assignable boolean DEFAULT true, _short_code text DEFAULT NULL::text, _source text DEFAULT NULL::text) returns SETOF auth.permission
    rows 1
    language sql
as
$$
select *
from unsecure.create_permission('system', 1, null, _title, _parent_code, _is_assignable, _short_code, _source);
$$;

create or replace function unsecure.get_all_permissions(_requested_by text, _user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__permission_id integer, __is_assignable boolean, __title text, __code text, __full_code text, __has_children boolean, __short_code text, __source text)
    language plpgsql
as
$$
begin
	return query select permission_id, is_assignable, title, code, full_code::text, has_children, short_code, source
							 from auth.permission
							 order by full_code;
	-- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function unsecure.get_perm_sets(_requested_by text, _user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __title text, __code text, __is_system boolean, __is_assignable boolean, __permissions jsonb, __source text)
    language plpgsql
as
$$
begin
	return query
		select ps.perm_set_id
				 , ps.title
				 , ps.code
				 , ps.is_system
				 , ps.is_assignable
				 , jsonb_agg(jsonb_build_object('code', p.full_code, 'title', p.title, 'id',
																				p.permission_id))
				 , ps.source
		from auth.perm_set ps
					 inner join auth.perm_set_perm psp on ps.perm_set_id = psp.perm_set_id
					 inner join auth.permission p on p.permission_id = psp.permission_id
		where ps.tenant_id = _tenant_id
		group by ps.perm_set_id, ps.title, ps.code, ps.is_system, ps.is_assignable, ps.source;

	-- Read operation - journal message omitted (use journal level 'all' to log reads)

end;
$$;

create or replace function unsecure.create_perm_set(_created_by text, _user_id bigint, _correlation_id text, _title text, _is_system boolean DEFAULT false, _is_assignable boolean DEFAULT true, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1, _source text DEFAULT NULL::text) returns SETOF auth.perm_set
    rows 1
    language plpgsql
as
$$
declare
	__last_id int;
begin

	if
		exists(select
					 from unnest(_permissions) as perm_code
									inner join auth.permission p
														 on p.full_code = perm_code::ext.ltree and not p.is_assignable) then
		perform error.raise_52178();
	end if;

	-- noinspection SqlInsertValues
	insert into auth.perm_set(created_by, updated_by, tenant_id, title, is_system, is_assignable, source)
	values (_created_by, _created_by, _tenant_id, _title, _is_system, _is_assignable, _source)
	returning perm_set_id
		into __last_id;

	insert into auth.perm_set_perm(created_by, perm_set_id, permission_id)
	select _created_by, __last_id, p.permission_id
	from unnest(_permissions) as perm_code
				 inner join auth.permission p
										on p.full_code = perm_code::ext.ltree;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12020  -- perm_set_created
			, 'perm_set', __last_id
			, jsonb_build_object('perm_set_code', _title, 'tenant_title', _tenant_id::text
				, 'is_system', _is_system, 'is_assignable', _is_assignable
				, 'permissions', array_to_string(_permissions, ', '))
			, _tenant_id);

	return query
		select *
		from auth.perm_set
		where perm_set_id = __last_id;
end;
$$;

create or replace function unsecure.create_perm_set_as_system(_title text, _is_system boolean DEFAULT false, _is_assignable boolean DEFAULT true, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1, _source text DEFAULT NULL::text) returns SETOF auth.perm_set
    rows 1
    language sql
as
$$

select *
from unsecure.create_perm_set('system', 1, null, _title, _is_system, _is_assignable, _permissions, _tenant_id, _source);

$$;

create or replace function unsecure.update_perm_set(_updated_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _title text, _is_assignable boolean DEFAULT true, _tenant_id integer DEFAULT 1) returns SETOF auth.perm_set
    rows 1
    language plpgsql
as
$$
declare
	__last_id            int;
	__old_is_assignable  bool;
begin

	-- Check if is_assignable is changing (needed for cache invalidation)
	select is_assignable
	from auth.perm_set
	where perm_set_id = _perm_set_id
	into __old_is_assignable;

	-- noinspection SqlInsertValues
	update perm_set
	set updated_at    = now()
		, updated_by    = _updated_by
		, title         = _title
		, is_assignable = _is_assignable
	where perm_set_id = _perm_set_id
	returning perm_set_id
		into __last_id;

	-- If assignability changed, invalidate cache for all affected users
	if __old_is_assignable is distinct from _is_assignable then
		perform unsecure.invalidate_perm_set_users_permission_cache(_updated_by, _perm_set_id, _tenant_id);
	end if;

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 12021  -- perm_set_updated
			, 'perm_set', __last_id
			, jsonb_build_object('perm_set_code', _title, 'is_assignable', _is_assignable)
			, _tenant_id);

	return query
		select *
		from auth.perm_set
		where perm_set_id = __last_id;
end;
$$;

create or replace function unsecure.add_perm_set_permissions(_created_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __perm_set_code text, __permission_id integer, __permission_code text)
    rows 1
    language plpgsql
as
$$
begin

	if
		not exists(select from auth.perm_set where perm_set_id = _perm_set_id and tenant_id = _tenant_id) then
		perform error.raise_52177(_perm_set_id, _tenant_id);
	end if;

	insert into auth.perm_set_perm(created_by, perm_set_id, permission_id)
	select _created_by, _perm_set_id, p.permission_id
	from unnest(_permissions) as perm_code
				 left join auth.permission p
									 on p.full_code = perm_code::ext.ltree
				 left join auth.perm_set_perm psp on p.permission_id = psp.permission_id and psp.perm_set_id = _perm_set_id
				 left join auth.perm_set ps on psp.perm_set_id = ps.perm_set_id
	where p.code is not null
		and psp.perm_set_id is null;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12021  -- perm_set_updated
			, 'perm_set', _perm_set_id
			, jsonb_build_object('perm_set_code', _perm_set_id::text
				, 'permissions_added', array_to_string(_permissions, ', '))
			, _tenant_id);

	-- Invalidate permission cache for all users who have this perm_set assigned
	perform unsecure.invalidate_perm_set_users_permission_cache(_created_by, _perm_set_id, _tenant_id);

	return query
		select ps.perm_set_id, ps.code, p.permission_id, p.full_code::text
		from auth.perm_set ps
					 inner join auth.perm_set_perm psp on ps.perm_set_id = psp.perm_set_id
					 inner join auth.permission p on p.permission_id = psp.permission_id
		where ps.perm_set_id = _perm_set_id
			and ps.tenant_id = _tenant_id
		order by p.full_code::text;
end;
$$;

create or replace function unsecure.delete_perm_set_permissions(_deleted_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __perm_set_code text, __permission_id integer, __permission_code text)
    rows 1
    language plpgsql
as
$$
begin

	if
		not exists(select from auth.perm_set where perm_set_id = _perm_set_id and tenant_id = _tenant_id) then
		perform error.raise_52177(_perm_set_id, _tenant_id);
	end if;

	delete
	from auth.perm_set_perm
	where perm_set_id = _perm_set_id
		and permission_id in (select p.permission_id
													from unnest(_permissions) as perm_code
																 inner join auth.permission p on p.full_code = perm_code::ext.ltree
																 inner join auth.perm_set_perm psp
																						on p.permission_id = psp.permission_id and psp.perm_set_id = _perm_set_id
																 inner join auth.perm_set ps
																						on psp.perm_set_id = ps.perm_set_id and ps.tenant_id = _tenant_id);

	perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
			, 12021  -- perm_set_updated
			, 'perm_set', _perm_set_id
			, jsonb_build_object('perm_set_code', _perm_set_id::text
				, 'permissions_removed', array_to_string(_permissions, ', '))
			, _tenant_id);

	-- Invalidate permission cache for all users who have this perm_set assigned
	perform unsecure.invalidate_perm_set_users_permission_cache(_deleted_by, _perm_set_id, _tenant_id);

	return query
		select ps.perm_set_id, ps.code, p.permission_id, p.full_code::text
		from auth.perm_set ps
					 inner join auth.perm_set_perm psp on ps.perm_set_id = psp.perm_set_id
					 inner join auth.permission p on p.permission_id = psp.permission_id
		where ps.perm_set_id = _perm_set_id
			and ps.tenant_id = _tenant_id
		order by p.full_code::text;
end;
$$;

create or replace function unsecure.update_last_used_provider(_target_user_id bigint, _provider_code text) returns void
    language sql
as
$$
update auth.user_info
set last_used_provider_code = _provider_code
where user_id = _target_user_id;
$$;

create or replace function unsecure.create_user_info(_created_by text, _user_id bigint, _correlation_id text, _username text, _email text, _display_name text, _last_provider_code text) returns SETOF auth.user_info
    rows 1
    language plpgsql
as
$$
declare
	__last_id             bigint;
	__normalized_username text;
	__normalized_email    text;
begin
	__normalized_username := lower(trim(_username));
	__normalized_email := lower(trim(_email));

	select user_id
	from auth.user_info
	where username = __normalized_username
	into __last_id;

	if
		__last_id is null then
		insert into auth.user_info ( created_by, updated_by, user_type_code, username, original_username, email
															 , display_name, last_used_provider_code)
		values ( _created_by, _created_by, 'normal', __normalized_username, trim(_username), __normalized_email
					 , _display_name, _last_provider_code)
		returning user_id into __last_id;
	end if;

	return query
		select *
		from auth.user_info
		where user_id = __last_id;

	perform create_journal_message_for_entity('system', _user_id, _correlation_id
			, 10001  -- user_created
			, 'user', __last_id
			, jsonb_build_object('username', __normalized_username, 'email', __normalized_email
				, 'display_name', _display_name)
			, 1);
end;
$$;

create or replace function unsecure.create_service_user_info(_created_by text, _user_id bigint, _correlation_id text, _username text, _display_name text, _email text DEFAULT NULL::text, _custom_service_user_id bigint DEFAULT NULL::bigint) returns SETOF auth.user_info
    rows 1
    language plpgsql
as
$$
declare
	__last_id              bigint;
	__last_service_user_id bigint;
	__normalized_username  text;
	__normalized_email     text;
begin
	__normalized_username := lower(trim(_username));
	__normalized_email := lower(trim(_email));

	__last_service_user_id := _custom_service_user_id;

	if (__last_service_user_id is null) then
		select max(user_id)
		from auth.user_info
		where user_id between 1::bigint and 999::bigint
		into __last_service_user_id;
	end if;

	if (__last_service_user_id is null) then
		insert into auth.user_info ( created_by, updated_by, user_type_code, username, original_username, email
															 , display_name)
		values ( _created_by, _created_by, 'service', __normalized_username, trim(_username), __normalized_email
					 , _display_name)
		returning user_id
			into __last_id;
	else
		insert into auth.user_info ( created_by, updated_by, user_id, user_type_code, username, original_username, email
															 , display_name)
		values ( _created_by, _created_by, __last_service_user_id + 1
					 , 'service'
					 , __normalized_username, trim(_username)
					 , __normalized_email, _display_name)
		returning user_id
			into __last_id;
	end if;

	return query
		select *
		from auth.user_info
		where user_id = __last_id;

	perform create_journal_message_for_entity('system', _user_id, _correlation_id
			, 10001  -- user_created
			, 'user', __last_id
			, jsonb_build_object('username', __normalized_username, 'email', __normalized_email
				, 'display_name', _display_name, 'user_type', 'service')
			, 1);
end;
$$;

create or replace function unsecure.update_user_password(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _password_hash text DEFAULT NULL::text, _password_salt text DEFAULT NULL::text)
    returns TABLE(__user_id bigint, __provider_code text, __provider_uid text)
    rows 1
    language plpgsql
as
$$
begin

	return query
		update auth.user_identity
			set updated_at = now(),
				updated_by = _updated_by, password_hash = _password_hash, password_salt = _password_salt
			where user_id = _target_user_id
				and provider_code = 'email'
			returning user_id
				, provider_code
				, uid;

	perform create_journal_message_for_entity('system', _user_id, _correlation_id
			, 10020  -- password_changed
			, 'user', _target_user_id
			, jsonb_build_object('username', _target_user_id::text)
			, 1);
end;
$$;

create or replace function unsecure.add_user_to_default_groups(_created_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_id bigint, __user_group_id integer, __user_group_code text, __user_group_title text)
    language plpgsql
as
$$
declare
	group_data RECORD;
begin

	if
		not exists(select from auth.user_info where user_id = _user_id) then
		perform error.raise_52103(_user_id);
	end if;

	drop table if exists tmp_default_groups;

	create
		temporary table tmp_default_groups as
	select aug.user_group_id
	from auth.active_user_groups aug
	where aug.tenant_id = _tenant_id
		and aug.is_default
		and user_group_id not in (select user_group_id
															from auth.user_group_member ugm
																		 inner join auth.user_group ug on ug.user_group_id = ugm.user_group_id
															where ugm.user_id = _target_user_id
																and ug.tenant_id = _tenant_id
																and ug.is_default);


	for group_data in
		select dg.*
		from tmp_default_groups dg
		loop
			perform unsecure.create_user_group_member(_created_by, _user_id, _correlation_id, group_data.user_group_id,
																								_target_user_id,
																								_tenant_id) member;
		end loop;

	return query
		select user_id, user_group_id, group_code, group_title
		from auth.user_group_members ugms
		where ugms.tenant_id = _tenant_id
			and ugms.user_id = _target_user_id;

	drop table tmp_default_groups;
end;
$$;

create or replace function unsecure.create_api_user(_created_by text, _user_id bigint, _correlation_id text, _api_key text, _tenant_id integer DEFAULT 1) returns SETOF auth.user_info
    rows 1
    language plpgsql
as
$$
declare
	__last_id             bigint;
	__normalized_username text;
begin
	__normalized_username := 'api_key_' || _api_key;

	insert into auth.user_info (created_by, updated_by, user_type_code, code, username, original_username, display_name)
	values ( _created_by, _created_by, 'api', __normalized_username, __normalized_username, __normalized_username
				 , __normalized_username)
	returning user_id into __last_id;

	return query
		select *
		from auth.user_info
		where user_id = __last_id;

	perform create_journal_message_for_entity('system', _user_id, _correlation_id
			, 10001  -- user_created
			, 'user', __last_id
			, jsonb_build_object('username', __normalized_username, 'user_type', 'api')
			, _tenant_id);
end;
$$;

create or replace function unsecure.update_user_info_basic_data(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _username text, _display_name text, _email text DEFAULT NULL::text)
    returns TABLE(__user_info_id bigint)
    language plpgsql
as
$$
begin
	update auth.user_info
	set updated_at        = now(),
			updated_by        = _updated_by,
			username          = trim(lower(_username)),
			original_username = _username,
			display_name      = _display_name,
			email             = _email
	where user_id = _target_user_id;

	perform auth.create_user_event(_updated_by, _user_id, _correlation_id, 'update_user_info', _target_user_id);

	perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
			, 10002  -- user_updated
			, 'user', _target_user_id
			, jsonb_build_object('username', _username, 'display_name', _display_name, 'email', _email)
			, 1);
end;
$$;

create or replace function unsecure.create_user_group_member(_created_by text, _user_id bigint, _correlation_id text, _user_group_id integer, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__user_group_member_id bigint)
    rows 1
    language plpgsql
as
$$
declare
	__is_assignable   bool;
	__is_external     bool;
	__is_active       bool;
	__user_group_code text;
	__user_upn        text;
begin

	select is_assignable, is_external, is_active
	from auth.user_group ug
	where ug.user_group_id = _user_group_id
	into __is_assignable, __is_external, __is_active;

	if __is_active is null then
		perform error.raise_52171(_user_group_id);
	end if;

	if not __is_active then
		perform error.raise_52172(_user_group_id);
	end if;

	if not __is_assignable or __is_external then
		perform error.raise_52173(_user_group_id);
	end if;

	select code
	from auth.user_group
	where user_group_id = _user_group_id
	into __user_group_code;

	select code
	from auth.user_info
	where user_id = _target_user_id
	into __user_upn;

	return query insert into auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
		values (_created_by, _user_group_id, _target_user_id, 'manual')
		returning member_id;

	-- Invalidate permission cache so user picks up group permissions immediately
	perform unsecure.clear_permission_cache(_created_by, _target_user_id, _tenant_id);

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 13010  -- group_member_added
			, 'group', _user_group_id
			, jsonb_build_object('username', __user_upn, 'group_title', __user_group_code
				, 'target_user_id', _target_user_id)
			, _tenant_id);
end;
$$;

create or replace function unsecure.get_user_group_members(_requested_by text, _user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__created timestamp with time zone, __created_by text, __member_id bigint, __member_type_code text, __user_id bigint, __user_display_name text, __user_is_system boolean, __user_is_active boolean, __user_is_locked boolean, __mapping_id integer, __mapping_mapped_object_name text, __mapping_provider_code text)
    rows 1
    language plpgsql
as
$$
begin

	if
		(not exists(select
								from auth.user_group
								where user_group_id = _user_group_id
									and (tenant_id = _tenant_id or _tenant_id = 1))) then
		perform error.raise_52171(_user_group_id);
	end if;

	return query
		select ugm.created_at
				 , ugm.created_by
				 , ugm.member_id
				 , ugm.member_type_code
				 , ugm.user_id
				 , ui.display_name
				 , ui.is_system
				 , ui.is_active
				 , ui.is_locked
				 , ugm.mapping_id
				 , ugma.mapped_object_name
				 , ugma.provider_code
		from auth.user_group_member ugm
					 left join auth.user_group_mapping ugma on ugma.user_group_mapping_id = ugm.mapping_id
					 inner join auth.user_info ui on ui.user_id = ugm.user_id
		where ugm.user_group_id = _user_group_id;

-- OMITTING UNTIL JOURNAL MESSAGES HAVE LEVELS
-- 	perform
-- 		add_journal_msg(_requested_by, _user_id
-- 			, format('User: %s requested user group members: %s in tenant: %s'
-- 											, _requested_by, _user_group_id, _tenant_id)
-- 			, 'group', _user_group_id
-- 			, null
-- 			, 50210
-- 			, _tenant_id := _tenant_id);
end;
$$;

create or replace function unsecure.create_user_identity(_created_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text, _provider_uid text, _provider_oid text, _password_hash text DEFAULT NULL::text, _user_data text DEFAULT NULL::text, _password_salt text DEFAULT NULL::text, _is_active boolean DEFAULT false)
    returns TABLE(__user_id bigint, __provider_code text, __provider_uid text)
    rows 1
    language plpgsql
as
$$
declare
	__user_info auth.user_info;
begin

	select *
	from auth.user_info
	where user_id = _target_user_id
	into __user_info;

	return query insert into auth.user_identity (created_by, updated_by, user_id, provider_code, uid, provider_oid,
																							 user_data, password_hash, password_salt, is_active)
		values ( _created_by, _created_by, _target_user_id, _provider_code, _provider_uid, _provider_oid, _user_data::jsonb
					 , _password_hash
					 , _password_salt, _is_active)
		returning user_id, provider_code, uid;

	perform create_journal_message_for_entity('system', _user_id, _correlation_id
			, 10030  -- identity_created
			, 'user', _target_user_id
			, jsonb_build_object('username', __user_info.username, 'provider_code', _provider_code
				, 'provider_uid', _provider_uid, 'provider_oid', _provider_oid, 'is_active', _is_active)
			, 1);
end;
$$;

create or replace function unsecure.delete_tenant(_deleted_by text, _user_id bigint, _correlation_id text, _tenant_id integer)
    returns TABLE(__tenant_id integer, __uuid uuid, __code text)
    language plpgsql
as
$$
declare
    __last_item auth.tenant;
begin

    delete
    from auth.tenant
    where tenant_id = _tenant_id
    returning * into __last_item;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id
            , 11003  -- tenant_deleted
            , 'tenant', __last_item.tenant_id
            , jsonb_build_object('tenant_title', __last_item.title, 'tenant_code', __last_item.code)
            , 1);


    return query
        select __last_item.tenant_id
             , __last_item.uuid
             , __last_item.code;
end;
$$;

create or replace function unsecure.recalculate_user_groups(_created_by text, _target_user_id bigint, _provider_code text)
    returns TABLE(__tenant_id integer, __user_group_id integer, __user_group_code text)
    language plpgsql
as
$$
declare
    __not_really_used int;
    __provider_groups text[];
    __provider_roles  text[];
begin

    -- Validate provider code exists (prevent silent failures with NULL arrays)
    if _provider_code is not null and not exists(select 1 from auth.provider where code = _provider_code) then
        raise exception 'Provider "%" does not exist', _provider_code
            using errcode = '22023';  -- invalid_parameter_value
    end if;

    select provider_groups
         , provider_roles
    from auth.user_identity
    where provider_code = _provider_code
      and user_id = _target_user_id
    into __provider_groups, __provider_roles;

    insert into auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    select _created_by, ug.user_group_id, _target_user_id, 'manual'
    from auth.user_group ug
    where is_default
    on conflict (user_group_id, user_id, coalesce(mapping_id, 0)) do nothing;

    -- cleanup membership of groups user is no longer part of
    with affected_deleted_group_tenants as (
        delete
            from auth.user_group_member
                where user_id = _target_user_id
                    and mapping_id is not null
                    and user_group_id not in (
                        select distinct ugm.user_group_id
                        from unnest(__provider_groups) g
                                 inner join auth.user_group_mapping ugm
                                            on ugm.provider_code = _provider_code and ugm.mapped_object_id = lower(g)
                                 inner join auth.user_group u
                                            on u.user_group_id = ugm.user_group_id
                        union
                        select distinct ugm.user_group_id
                        from unnest(__provider_roles) r
                                 inner join auth.user_group_mapping ugm
                                            on ugm.provider_code = _provider_code and ugm.mapped_role = lower(r)
                                 inner join auth.user_group u
                                            on u.user_group_id = ugm.user_group_id)
                returning user_group_id)
       , affected_group_tenants as (
        insert
            into auth.user_group_member (created_by, user_id, user_group_id, mapping_id, member_type_code)
                select distinct _created_by
                              , _target_user_id
                              , ugm.user_group_id
                              , ugm.user_group_mapping_id
                              , 'external'
                from unnest(__provider_groups) g
                         inner join auth.user_group_mapping ugm
                                    on ugm.provider_code = _provider_code and ugm.mapped_object_id = lower(g)
                where ugm.user_group_id not in (
                    select user_group_id
                    from auth.user_group_member
                    where user_id = _target_user_id)
                returning user_group_id)
       , affected_role_tenants as (
        insert
            into auth.user_group_member (created_by, user_id, user_group_id, mapping_id, member_type_code)
                select distinct _created_by
                              , _target_user_id
                              , ugm.user_group_id
                              , ugm.user_group_mapping_id
                              , 'external'
                from unnest(__provider_roles) r
                         inner join auth.user_group_mapping ugm
                                    on ugm.provider_code = _provider_code and ugm.mapped_role = lower(r)
                where ugm.user_group_id not in (
                    select user_group_id
                    from auth.user_group_member
                    where user_id = _target_user_id)
                returning user_group_id)
       , all_group_ids as (
        select user_group_id
        from affected_deleted_group_tenants
        union
        select user_group_id
        from affected_group_tenants
        union
        select user_group_id
        from affected_role_tenants)
       , all_tenants as (
        select tenant_id
        from all_group_ids ids
                 inner join auth.user_group ug
                            on ids.user_group_id = ug.user_group_id
        group by tenant_id)
       -- variable not really used, it's there just to avoid 'query has no destination for result data'
    select at.tenant_id
    from all_tenants at
       , lateral unsecure.clear_permission_cache(_created_by, _target_user_id, at.tenant_id) r
    into __not_really_used;

    return query
        select distinct ug.tenant_id
                      , ug.user_group_id
                      , ug.code
        from auth.user_group_member ugm
                 inner join auth.user_group ug on ug.user_group_id = ugm.user_group_id
        where ugm.user_id = _target_user_id;
end;
$$;

create or replace function unsecure.recalculate_user_permissions(_created_by text, _target_user_id bigint, _tenant_id integer DEFAULT NULL::integer)
    returns TABLE(__tenant_id integer, __tenant_uuid uuid, __groups text[], __permissions text[], __short_code_permissions text[])
    language plpgsql
as
$$
declare
    __perm_cache_timeout_in_s bigint;
    __expiration_date         timestamptz;
    __is_active               boolean;
    __is_locked               boolean;
begin

    -- Check if user is active and not locked
    select is_active, is_locked
    from auth.user_info
    where user_id = _target_user_id
    into __is_active, __is_locked;

    if __is_active is null then
        perform error.raise_33001(_target_user_id, null);
    end if;

    if not __is_active then
        perform error.raise_33003(_target_user_id);
    end if;

    if __is_locked then
        perform error.raise_33004(_target_user_id);
    end if;

    if _tenant_id is not null and exists(
            select
            from auth.user_permission_cache
            where tenant_id = _tenant_id
              and user_id = _target_user_id
              and expiration_date > now())
    then

        return query
            select _tenant_id
                 , upc.tenant_uuid
                 , upc.groups
                 , upc.permissions
                 , upc.short_code_permissions
            from auth.user_permission_cache upc
            where upc.tenant_id = _tenant_id
              and upc.user_id = _target_user_id;
    else
        select number_value
        from const.sys_param sp
        where sp.group_code = 'auth'
          and sp.code = 'perm_cache_timeout_in_s'
        into __perm_cache_timeout_in_s;

        if
            (__perm_cache_timeout_in_s is null)
        then
            __perm_cache_timeout_in_s := 300;
        end if;

        create temporary table __temp_users_groups_permissions
        (
            tenant_id                integer,
            tenant_uuid              uuid,
            group_codes              text[],
            permission_codes         text[],
            short_code_permission_codes text[]
        ) on commit drop;

        with ugs as (
            select ugm.tenant_id
                 , t.uuid as tenant_uuid
                 , user_group_id
                 , group_code
            from auth.user_group_members ugm
                     inner join auth.tenant t on t.tenant_id = ugm.tenant_id
            where ugm.user_id = _target_user_id)
           , group_assignments as (
            select distinct pa.tenant_id
                          , ug.tenant_uuid
                          , ep.permission_code as full_code
                          , ep.permission_short_code as short_code
            from ugs ug
                     inner join auth.permission_assignment pa
                                on ug.user_group_id = pa.user_group_id
                     inner join auth.effective_permissions ep on pa.perm_set_id = ep.perm_set_id
            where ep.perm_set_is_assignable = true
              and ep.permission_is_assignable = true
            union
            select distinct pa.tenant_id
                          , ug.tenant_uuid
                          , sp.full_code
                          , sp.short_code
            from ugs ug
                     inner join auth.permission_assignment pa
                                on ug.user_group_id = pa.user_group_id
                     inner join auth.permission p on pa.permission_id = p.permission_id
                     inner join auth.permission sp
                                on sp.node_path <@ p.node_path and sp.is_assignable = true)
           , user_assignments as (
            select distinct pa.tenant_id
                          , t.uuid             as tenant_uuid
                          , ep.permission_code as full_code
                          , ep.permission_short_code as short_code
            from auth.permission_assignment pa
                     inner join auth.tenant t on pa.tenant_id = t.tenant_id
                     inner join auth.effective_permissions ep
                                on pa.perm_set_id = ep.perm_set_id
            where pa.user_id = _target_user_id
              and ep.perm_set_is_assignable = true
              and ep.permission_is_assignable = true
            union
            select distinct pa.tenant_id
                          , t.uuid as tenant_uuid
                          , sp.full_code
                          , sp.short_code
            from auth.permission_assignment pa
                     inner join auth.tenant t on pa.tenant_id = t.tenant_id
                     inner join auth.permission p
                                on pa.permission_id = p.permission_id
                     inner join auth.permission sp
                                on sp.node_path <@ p.node_path and sp.is_assignable = true
            where pa.user_id = _target_user_id)
           , user_permissions as (
            select distinct ga.tenant_id
                          , ga.tenant_uuid
                          , ga.full_code
                          , ga.short_code
            from group_assignments ga
            union
            select ua.tenant_id
                 , ua.tenant_uuid
                 , ua.full_code
                 , ua.short_code
            from user_assignments ua
            order by full_code)
        insert
        into __temp_users_groups_permissions(tenant_id, tenant_uuid, group_codes, permission_codes, short_code_permission_codes)
        select data.tenant_id
             , data.tenant_uuid
             , coalesce(array_agg(distinct data.groups) filter ( where data.groups is not null ), array []::text[])
             , coalesce(array_agg(distinct data.perms) filter ( where data.perms is not null ), array []::text[])
             , coalesce(array_agg(distinct data.short_code_perms) filter ( where data.short_code_perms is not null ), array []::text[])
        from (
                 select ug.tenant_id
                      , ug.tenant_uuid
                      , ug.group_code as groups
                      , null          as perms
                      , null          as short_code_perms
                 from ugs ug
                 union
                 select up.tenant_id
                      , up.tenant_uuid
                      , null
                      , up.full_code::text
                      , up.short_code
                 from user_permissions up) data
        group by data.tenant_id, data.tenant_uuid;

        __expiration_date := now() + interval '1 second' * __perm_cache_timeout_in_s;

        insert into auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions,
                                                short_code_permissions, expiration_date)
        select _created_by
             , _target_user_id
             , tugp.tenant_id
             , tugp.tenant_uuid
             , tugp.group_codes
             , tugp.permission_codes
             , tugp.short_code_permission_codes
             , __expiration_date
        from __temp_users_groups_permissions tugp
        on conflict (user_id, tenant_id )
            do update
            set updated_at              = now()
              , updated_by              = _created_by
              , groups                  = excluded.groups
              , permissions             = excluded.permissions
              , short_code_permissions  = excluded.short_code_permissions
              , expiration_date         = __expiration_date;

        return query
            select ugp.tenant_id
                 , ugp.tenant_uuid
                 , ugp.group_codes
                 , ugp.permission_codes
                 , ugp.short_code_permission_codes
            from __temp_users_groups_permissions ugp
            where _tenant_id is null
               or ugp.tenant_id = _tenant_id
            order by ugp.tenant_id;
    end if;
end;
$$;

create or replace function unsecure.update_user_identity_uid_oid(_updated_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text, _provider_uid text, _provider_oid text) returns void
    language plpgsql
as
$$
declare
	__upn              text;
	__current_oid      text;
	__current_uid      text;
	__user_identity_id bigint;
begin

	select username
	from auth.user_info ui
	where ui.user_id = _user_id
	into __upn;

	select user_identity_id, uid, provider_oid
	from auth.user_identity uid
	where uid.user_id = _target_user_id
		and provider_code = _provider_code
	into __user_identity_id, __current_uid, __current_oid;

	if __current_uid <> _provider_uid then

		update auth.user_identity
		set uid = _provider_uid
		where user_identity_id = __user_identity_id;

		perform create_journal_message_for_entity('system', _user_id, _correlation_id
				, 10031  -- identity_updated
				, 'user', _target_user_id
				, jsonb_build_object('username', __upn, 'provider_code', _provider_code
					, 'provider_uid', _provider_uid)
				, 1);
	end if;

	if __current_oid <> _provider_oid then

		update auth.user_identity
		set provider_oid = _provider_oid
		where user_identity_id = __user_identity_id;

		perform create_journal_message_for_entity('system', _user_id, _correlation_id
				, 10031  -- identity_updated
				, 'user', _target_user_id
				, jsonb_build_object('username', __upn, 'provider_code', _provider_code
					, 'provider_oid', _provider_oid)
				, 1);
	end if;
end;
$$;

create or replace function unsecure.copy_perm_set(_created_by text, _user_id bigint, _correlation_id text, _source_perm_set_code text, _source_tenant_id integer, _target_tenant_id integer, _new_title text DEFAULT NULL::text) returns SETOF auth.perm_set
    language plpgsql
as
$$
declare
	__created_perm_set   auth.perm_set;
	__source_perm_set    auth.perm_set;
	__source_tenant_code text;
	__target_tenant_code text;
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

	insert into auth.perm_set(created_by, updated_by, tenant_id, title, is_system,
														is_assignable, code, source)
	values ( _created_by, _created_by, _target_tenant_id, coalesce(_new_title, __source_perm_set.title)
				 , __source_perm_set.is_system, __source_perm_set.is_assignable, helpers.get_code(_new_title)
				 , __source_perm_set.source)
	returning *
		into __created_perm_set;

-- copy assigned permissions

	insert into auth.perm_set_perm (created_by, perm_set_id, permission_id)
	select _created_by, __created_perm_set.perm_set_id, permission_id
	from auth.perm_set_perm
	where perm_set_id = __source_perm_set.perm_set_id;

	perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
			, 12020  -- perm_set_created
			, 'perm_set', __created_perm_set.perm_set_id
			, jsonb_build_object('perm_set_code', __created_perm_set.code
				, 'tenant_title', __target_tenant_code
				, 'source_perm_set_code', _source_perm_set_code
				, 'source_tenant', __source_tenant_code)
			, _target_tenant_id);

	return query select * from auth.perm_set where perm_set_id = __created_perm_set.perm_set_id;
end;
$$;

create or replace function unsecure.get_user_assigned_permissions(_requested_by text, _user_id bigint, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__permissions jsonb, __perm_set_title text, __perm_set_id integer, __perm_set_code text, __assignment_id bigint, __user_group_id integer)
    language plpgsql
as
$$
begin
    return query with assigments as (
        select pa.*
        from auth.permission_assignment pa
                 left join auth.user_group_member ugm on pa.user_group_id = ugm.user_group_id
        where (ugm.user_id = _target_user_id
            or pa.user_id = _target_user_id)
          and tenant_id = _tenant_id)
                 select jsonb_agg(jsonb_build_object('code', p.full_code, 'title', p.title, 'id',
                                                     p.permission_id))
                                as permissions
                      , ps.title
                      , ps.perm_set_id
                      , ps.code as perm_set_code
                      , a.assignment_id
                      , a.user_group_id
                 from assigments a
                          left join auth.perm_set ps on a.perm_set_id = ps.perm_set_id
                          left join auth.perm_set_perm psp on ps.perm_set_id = psp.perm_set_id
                          left join auth.permission p
                                    on (coalesce(a.permission_id, psp.permission_id) = p.permission_id)
                 group by ps.title, ps.perm_set_id, a.assignment_id, a.user_group_id
                 order by ps.title nulls last;


    -- Read operation - journal message omitted (use journal level 'all' to log reads)
end;
$$;

create or replace function unsecure.purge_journal(
    _deleted_by text, _user_id bigint, _correlation_id text,
    _older_than_days integer default null
) returns table(__deleted_count bigint)
    language plpgsql
as
$$
declare
    __retention_days integer;
    __count bigint;
begin
    __retention_days := coalesce(_older_than_days,
        (select text_value::integer from const.sys_param
         where group_code = 'journal' and code = 'retention_days'));

    if __retention_days is null then
        raise exception 'Retention days not specified and not configured in sys_param';
    end if;

    delete from public.journal
    where created_at < now() - make_interval(days => __retention_days);

    get diagnostics __count = row_count;

    return query select __count;
end;
$$;

create or replace function unsecure.purge_user_events(
    _deleted_by text, _user_id bigint, _correlation_id text,
    _older_than_days integer default null
) returns table(__deleted_count bigint)
    language plpgsql
as
$$
declare
    __retention_days integer;
    __count bigint;
begin
    __retention_days := coalesce(_older_than_days,
        (select text_value::integer from const.sys_param
         where group_code = 'user_event' and code = 'retention_days'));

    if __retention_days is null then
        raise exception 'Retention days not specified and not configured in sys_param';
    end if;

    delete from auth.user_event
    where created_at < now() - make_interval(days => __retention_days);

    get diagnostics __count = row_count;

    return query select __count;
end;
$$;

