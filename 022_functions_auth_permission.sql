/*
 * Auth Permission Functions
 * =========================
 *
 * Permission management: perm sets, assignments, has_permission checks
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.throw_no_access(_username text, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
	perform
		error.raise_52108(_tenant_id, _username);
end;
$$;

create or replace function internal.throw_no_permission(_user_id bigint, _perm_codes text[], _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
	perform
		error.raise_52109(_user_id, _perm_codes, _tenant_id);
end;
$$;

create or replace function internal.throw_no_permission(_user_id bigint, _perm_codes text[]) returns void
    language plpgsql
as
$$
begin
	perform
		error.raise_52109(_user_id, _perm_codes);
end;
$$;

create or replace function internal.throw_no_permission(_user_id bigint, _perm_code text, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
	perform
		internal.throw_no_permission(_user_id, array [_perm_code], _tenant_id);
end;
$$;

create or replace function internal.throw_no_permission(_user_id bigint, _perm_code text) returns void
    language plpgsql
as
$$
begin
	perform
		internal.throw_no_permission(_user_id, array [_perm_code], 1);
end;
$$;

create or replace function auth.has_permissions(_target_user_id bigint, _correlation_id text, _perm_codes text[], _tenant_id integer DEFAULT 1, _throw_err boolean DEFAULT true) returns boolean
    stable
    language plpgsql
as
$$
declare
    __perms                   text[];
    __expiration_date         timestamptz;
    __last_used_provider_code text;
begin

    if (_target_user_id = 1)
    then
        return true;
    end if;

    -- NOT REALLY SAFE FOR SOME INTERNAL/SYSTEM PERMISSIONS
    if (auth.is_owner(_target_user_id, _correlation_id, null, _tenant_id))
    then
        return true;
    end if;

    select permissions
         , expiration_date
    from auth.user_permission_cache upc
    where upc.tenant_id = _tenant_id -- this was originally, either _tenant_id or 1, but from now on it's just _tenant_id
      and user_id = _target_user_id
    into __perms, __expiration_date;


    if __expiration_date is null or __expiration_date <= now()
    then
        if not exists(
                select
                from auth.user_info ui
                where ui.user_id = _target_user_id)
        then
            perform error.raise_52103(_target_user_id);
        end if;

        select last_used_provider_code
        from auth.user_info
        where user_id = _target_user_id
        into __last_used_provider_code;

        perform unsecure.recalculate_user_groups('permission_check'
            , _target_user_id
            , __last_used_provider_code
            );

        select __permissions
        from unsecure.recalculate_user_permissions('permission_check', _target_user_id, _tenant_id)
        into __perms;

    end if;

    if exists(
            select
            from unnest(__perms) p
                     inner join unnest(_perm_codes) rp on p = rp)
    then
        return true;
    end if;

    if (_throw_err)
    then
        perform create_journal_message_for_entity('system', _target_user_id, _correlation_id
            , 32001  -- err_no_permission
            , 'perm', _target_user_id
            , jsonb_build_object('username', _target_user_id::text
                , 'permission_codes', array_to_string(_perm_codes, '; '))
            , _tenant_id);

        perform
            internal.throw_no_permission(_target_user_id, _perm_codes, _tenant_id);
    end if;

    return false;
end ;
$$;

create or replace function auth.has_permission(_target_user_id bigint, _correlation_id text, _perm_code text, _tenant_id integer DEFAULT 1, _throw_err boolean DEFAULT true) returns boolean
    stable
    language plpgsql
as
$$
begin
	return auth.has_permissions(_target_user_id, _correlation_id, array [_perm_code], _tenant_id, _throw_err);
end ;
$$;

create or replace function auth.get_effective_group_permissions(_requested_by text, _user_id bigint, _correlation_id text, _group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__full_code text, __permission_title text, __perm_set_title text, __perm_set_code text, __perm_set_id integer, __assignment_id bigint)
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, _correlation_id, 'groups.get_permissions', _tenant_id);

	return query select * from unsecure.get_effective_group_permissions(_requested_by, _user_id, _group_id, _tenant_id);
end;
$$;

create or replace function auth.get_assigned_group_permissions(_requested_by text, _user_id bigint, _correlation_id text, _user_group_id integer, _tenant_id integer DEFAULT 1)
    returns TABLE(__permissions jsonb, __perm_set_title text, __perm_set_id integer, __perm_set_code text, __assignment_id bigint)
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, _correlation_id, 'groups.get_permissions', _tenant_id);

	return query select *
							 from unsecure.get_assigned_group_permissions(_requested_by, _user_id, _user_group_id, _tenant_id);
end;
$$;

create or replace function auth.set_permission_as_assignable(_updated_by text, _user_id bigint, _correlation_id text, _permission_id integer DEFAULT NULL::integer, _permission_full_code text DEFAULT NULL::text, _is_assignable boolean DEFAULT true) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.update_permission');

	return query
		select *
		from unsecure.set_permission_as_assignable(_updated_by, _user_id, _correlation_id, _permission_id, _permission_full_code,
																							 _is_assignable);
end;
$$;

create or replace function auth.assign_permission(_created_by text, _user_id bigint, _correlation_id text, _user_group_id integer, _target_user_id bigint, _perm_set_code text, _perm_code text, _tenant_id integer DEFAULT 1) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.assign_permission', _tenant_id);

	return query
		select *
		from unsecure.assign_permission(_created_by, _user_id, _correlation_id
			, _user_group_id, _target_user_id
			, _perm_set_code
			, _perm_code
			, _tenant_id);
end;

$$;

create or replace function auth.unassign_permission(_deleted_by text, _user_id bigint, _correlation_id text, _assignment_id bigint, _tenant_id integer DEFAULT 1) returns SETOF auth.permission_assignment
    language plpgsql
as
$$
begin
	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.unassign_permission', _tenant_id);

	return query
		select *
		from unsecure.unassign_permission(_deleted_by, _user_id, _correlation_id, _assignment_id, _tenant_id);
end;
$$;

create or replace function auth.create_permission(_created_by text, _user_id bigint, _correlation_id text, _title text, _parent_full_code text DEFAULT NULL::text, _is_assignable boolean DEFAULT true, _short_code text DEFAULT NULL::text, _source text DEFAULT NULL::text) returns SETOF auth.permission
    rows 1
    language plpgsql
as
$$
declare
	__last_id     int;
	__p           ext.ltree;
	__parent_id   int;
	__parent_path text;
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.add_permission');

	return query
		select * from unsecure.create_permission(_created_by, _user_id, _correlation_id, _title, _parent_full_code, _is_assignable, _short_code, _source);
end;
$$;

create or replace function auth.get_all_permissions(_requested_by text, _user_id bigint, _correlation_id text, _tenant_id integer DEFAULT 1)
    returns TABLE(__permission_id integer, __is_assignable boolean, __title text, __code text, __full_code text, __has_children boolean, __short_code text, __source text)
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, _correlation_id, 'permissions.get_perm_sets', _tenant_id);

	return query select * from unsecure.get_all_permissions(_requested_by, _user_id, _tenant_id);
end;
$$;

create or replace function auth.get_perm_sets(_requested_by text, _user_id bigint, _correlation_id text, _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __title text, __code text, __is_system boolean, __is_assignable boolean, __permissions jsonb, __source text)
    language plpgsql
as
$$
begin
	perform auth.has_permission(_user_id, _correlation_id, 'permissions.get_perm_sets', _tenant_id);

	return query select * from unsecure.get_perm_sets(_requested_by, _user_id, _tenant_id);
end;
$$;

create or replace function auth.create_perm_set(_created_by text, _user_id bigint, _correlation_id text, _title text, _is_system boolean DEFAULT false, _is_assignable boolean DEFAULT true, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1, _source text DEFAULT NULL::text) returns SETOF auth.perm_set
    rows 1
    language plpgsql
as
$$
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.create_permission_set', _tenant_id);

	return query
		select *
		from unsecure.create_perm_set(_created_by, _user_id, _correlation_id, _title, _is_system, _is_assignable,
																	_permissions, _tenant_id, _source);
end;
$$;

create or replace function auth.update_perm_set(_updated_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _title text, _is_assignable boolean DEFAULT true, _tenant_id integer DEFAULT 1) returns SETOF auth.perm_set
    rows 1
    language plpgsql
as
$$
begin

	if
		not exists(select from auth.perm_set where perm_set_id = _perm_set_id and tenant_id = _tenant_id) then
		perform error.raise_52177(_perm_set_id, _tenant_id);

	end if;

	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.update_permission_set', _tenant_id);

	return query
		select *
		from unsecure.update_perm_set(_updated_by, _user_id, _correlation_id
			, _perm_set_id, _title, _is_assignable, _tenant_id);
end;
$$;

create or replace function auth.add_perm_set_permissions(_created_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __perm_set_code text, __permission_id integer, __permission_code text)
    rows 1
    language plpgsql
as
$$
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.update_permission_set', _tenant_id);

	return query
		select *
		from unsecure.add_perm_set_permissions(_created_by, _user_id, _correlation_id
			, _perm_set_id, _permissions, _tenant_id);
end;
$$;

create or replace function auth.delete_perm_set_permissions(_created_by text, _user_id bigint, _correlation_id text, _perm_set_id integer, _permissions text[] DEFAULT NULL::text[], _tenant_id integer DEFAULT 1)
    returns TABLE(__perm_set_id integer, __perm_set_code text, __permission_id integer, __permission_code text)
    rows 1
    language plpgsql
as
$$
begin

	perform
		auth.has_permission(_user_id, _correlation_id, 'permissions.update_permission_set', _tenant_id);

	return query
		select *
		from unsecure.delete_perm_set_permissions(_created_by, _user_id, _correlation_id
			, _perm_set_id, _permissions, _tenant_id);
end;
$$;

create or replace function auth.get_user_permissions(_user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__assignment_id bigint, __perm_set_code text, __perm_set_title text, __user_group_member_id bigint, __user_group_title text, __permission_inheritance_type text, __permission_code text, __permission_title text)
    stable
    language plpgsql
as
$$
begin
	if _user_id <> _target_user_id then
		perform auth.has_permission(_user_id, _correlation_id, 'users.get_permissions', _tenant_id);
	end if;

	return query
		select pa.assignment_id
				 , ps.code  as perm_set_code
				 , ps.title as perm_set_title
				 , ugm.member_id
				 , ug.title
				 , case
						 when ugm is not null then 'user_group'
						 when ps is not null then 'perm_set'
						 else 'assignment'
			end
				 , p.full_code::text
				 , p.title
		from auth.permission_assignment pa
					 left join auth.user_group ug on pa.user_group_id = ug.user_group_id
					 left join auth.user_group_member ugm on ug.user_group_id = ugm.user_group_id

					 left join auth.perm_set ps on ps.perm_set_id = pa.perm_set_id
					 left join auth.perm_set_perm psp on psp.perm_set_id = ps.perm_set_id

					 inner join auth.permission p on p.permission_id = pa.permission_id
			or p.permission_id = psp.permission_id
		where pa.user_id = _target_user_id
			 or ugm.user_id = _target_user_id;
end;
$$;

create or replace function auth.seed_permission_data() returns void
    language plpgsql
as
$$
begin

	-- Permissions: Authentication
	perform unsecure.create_permission_as_system('Authentication', null, false, _source := 'core');
	perform unsecure.create_permission_as_system('Get data', 'authentication', _source := 'core');
	perform unsecure.create_permission_as_system('Create auth event', 'authentication', _source := 'core');
	perform unsecure.create_permission_as_system('Read user events', 'authentication', _source := 'core');
	perform unsecure.create_permission_as_system('Ensure permissions', 'authentication', _source := 'core');
	perform unsecure.create_permission_as_system('Get users groups and permissions', 'authentication', _source := 'core');

	-- Permissions: Journal
	perform unsecure.create_permission_as_system('Journal', _is_assignable := true, _source := 'core');
	perform unsecure.create_permission_as_system('Read journal', 'journal', _is_assignable := true, _source := 'core');
	perform unsecure.create_permission_as_system('Read global journal', 'journal', _is_assignable := true, _source := 'core');
	perform unsecure.create_permission_as_system('Get payload', 'journal', _is_assignable := true, _source := 'core');
	perform unsecure.create_permission_as_system('Purge journal', 'journal', _is_assignable := true, _source := 'core');

	-- Permissions: Areas
	perform unsecure.create_permission_as_system('Areas', null, false, _source := 'core');
	perform unsecure.create_permission_as_system('Public', 'areas', _source := 'core');
	perform unsecure.create_permission_as_system('Admin', 'areas', _source := 'core');

	-- Permissions: Tokens
	perform unsecure.create_permission_as_system('Tokens', null, false, _source := 'core');
	perform unsecure.create_permission_as_system('Create token', 'tokens', true, _source := 'core');
	perform unsecure.create_permission_as_system('Validate token', 'tokens', true, _source := 'core');
	perform unsecure.create_permission_as_system('Set as used', 'tokens', true, _source := 'core');

	-- Permissions: Token configuration
	perform unsecure.create_permission_as_system('Token configuration', _source := 'core');
	perform unsecure.create_permission_as_system('Create token type', 'token_configuration', _source := 'core');
	perform unsecure.create_permission_as_system('Update token type', 'token_configuration', _source := 'core');
	perform unsecure.create_permission_as_system('Delete token type', 'token_configuration', _source := 'core');
	perform unsecure.create_permission_as_system('Read token types', 'token_configuration', _source := 'core');

	-- Permissions: Permissions management
	perform unsecure.create_permission_as_system('Permissions', null, false, _source := 'core');
	perform unsecure.create_permission_as_system('Create permission', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Update permission', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Delete permission', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Create permission set', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Update permission set', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Delete permission set', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Assign permission', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Unassign permission', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Get perm sets', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Read permissions', 'permissions', _source := 'core');
	perform unsecure.create_permission_as_system('Read perm sets', 'permissions', _source := 'core');

	-- Permissions: Users
	perform unsecure.create_permission_as_system('Users', _source := 'core');
	perform unsecure.create_permission_as_system('Create service user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Register user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Add to default groups', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Enable user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Disable user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Lock user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Unlock user', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Get user identity', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Enable user identity', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Disable user identity', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Change password', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Read user events', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Update user data', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Get data', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Get permissions', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Read users', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Delete system user info', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Delete user info', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Delete user identity', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Read user group memberships', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Update last selected tenant', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Get available tenants', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Get users groups and permissions', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Create user tenant preferences', 'users', _source := 'core');
	perform unsecure.create_permission_as_system('Update user tenant preferences', 'users', _source := 'core');

	-- Permissions: Tenants
	perform unsecure.create_permission_as_system('Tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Create tenant', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Update tenant', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Assign owner', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Assign group owner', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Get tenants', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Get users', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Get groups', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Read tenants', 'tenants', _source := 'core');
	perform unsecure.create_permission_as_system('Delete tenant', 'tenants', _source := 'core');

	-- Permissions: Providers
	perform unsecure.create_permission_as_system('Providers', _source := 'core');
	perform unsecure.create_permission_as_system('Create provider', 'providers', _source := 'core');
	perform unsecure.create_permission_as_system('Update provider', 'providers', _source := 'core');
	perform unsecure.create_permission_as_system('Delete provider', 'providers', _source := 'core');
	perform unsecure.create_permission_as_system('Get users', 'providers', _source := 'core');

	-- Permissions: Groups
	perform unsecure.create_permission_as_system('Groups', _source := 'core');
	perform unsecure.create_permission_as_system('Get group', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Get permissions', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Create group', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Update group', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Delete group', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Lock group', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Get groups', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Create member', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Delete member', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Get members', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Get mapping', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Create mapping', 'groups', _source := 'core');
	perform unsecure.create_permission_as_system('Delete mapping', 'groups', _source := 'core');

	-- Permissions: API keys
	perform unsecure.create_permission_as_system('Api keys', _source := 'core');
	perform unsecure.create_permission_as_system('Create api key', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Update api key', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Delete api key', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Update api secret', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Validate api key', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Search', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Update permissions', 'api_keys', _source := 'core');
	perform unsecure.create_permission_as_system('Read outbound secret', 'api_keys', _source := 'core');

	-- Permissions: Languages
	perform unsecure.create_permission_as_system('Languages', _source := 'core');
	perform unsecure.create_permission_as_system('Create language', 'languages', _source := 'core');
	perform unsecure.create_permission_as_system('Update language', 'languages', _source := 'core');
	perform unsecure.create_permission_as_system('Delete language', 'languages', _source := 'core');
	perform unsecure.create_permission_as_system('Read languages', 'languages', _source := 'core');

	-- Permissions: Translations
	perform unsecure.create_permission_as_system('Translations', _source := 'core');
	perform unsecure.create_permission_as_system('Create translation', 'translations', _source := 'core');
	perform unsecure.create_permission_as_system('Update translation', 'translations', _source := 'core');
	perform unsecure.create_permission_as_system('Delete translation', 'translations', _source := 'core');
	perform unsecure.create_permission_as_system('Read translations', 'translations', _source := 'core');
	perform unsecure.create_permission_as_system('Copy translations', 'translations', _source := 'core');

	-- Permissions: Resources
	perform unsecure.create_permission_as_system('Resources', null, false, _source := 'core');
	perform unsecure.create_permission_as_system('Create resource type', 'resources', _source := 'core');
	perform unsecure.create_permission_as_system('Grant access', 'resources', _source := 'core');
	perform unsecure.create_permission_as_system('Deny access', 'resources', _source := 'core');
	perform unsecure.create_permission_as_system('Revoke access', 'resources', _source := 'core');
	perform unsecure.create_permission_as_system('Update access', 'resources', _source := 'core');
	perform unsecure.create_permission_as_system('Get grants', 'resources', _source := 'core');

	-- Permission sets
	perform unsecure.create_perm_set_as_system('System admin', true, _is_assignable := true,
		_permissions := array ['tenants', 'providers', 'users', 'groups', 'journal', 'journal.purge_journal', 'api_keys', 'languages', 'translations', 'token_configuration',
			'tokens.create_token', 'tokens.validate_token', 'tokens.set_as_used',
			'authentication.get_data', 'authentication.create_auth_event', 'authentication.read_user_events',
			'authentication.ensure_permissions', 'authentication.get_users_groups_and_permissions',
			'resources'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Tenant creator', true, _is_assignable := true,
		_permissions := array ['tenants.create_tenant', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Tenant admin', true, _is_assignable := true,
		_permissions := array ['tenants', 'journal.read_journal', 'journal.get_payload', 'languages', 'translations'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Tenant owner', true, _is_assignable := true,
		_permissions := array ['groups', 'tenants.update_tenant', 'tenants.assign_owner',
			'tenants.get_users', 'journal.read_journal', 'journal.get_journal_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Tenant member', true, _is_assignable := true,
		_permissions := array ['tenants.get_groups', 'tenants.get_users'],
		_source := 'core');

	-- Human admin permission sets (composable)
	perform unsecure.create_perm_set_as_system('User manager', true, _is_assignable := true,
		_permissions := array ['users', 'authentication.read_user_events', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Group manager', true, _is_assignable := true,
		_permissions := array ['groups', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Permission manager', true, _is_assignable := true,
		_permissions := array ['permissions.create_permission', 'permissions.update_permission', 'permissions.delete_permission',
			'permissions.create_permission_set', 'permissions.update_permission_set', 'permissions.delete_permission_set',
			'permissions.assign_permission', 'permissions.unassign_permission',
			'permissions.get_perm_sets', 'permissions.read_permissions', 'permissions.read_perm_sets',
			'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Provider manager', true, _is_assignable := true,
		_permissions := array ['providers', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Token manager', true, _is_assignable := true,
		_permissions := array ['tokens.create_token', 'tokens.validate_token', 'tokens.set_as_used',
			'token_configuration', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Api key manager', true, _is_assignable := true,
		_permissions := array ['api_keys', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Auditor', true, _is_assignable := true,
		_permissions := array ['journal', 'authentication.read_user_events',
			'users.read_users', 'groups.get_group', 'groups.get_groups', 'tenants.read_tenants'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Resource manager', true, _is_assignable := true,
		_permissions := array ['resources', 'journal.read_journal', 'journal.get_payload'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Full admin', true, _is_assignable := true,
		_permissions := array ['tenants', 'providers', 'users', 'groups', 'journal', 'journal.purge_journal',
			'api_keys', 'languages', 'translations', 'token_configuration', 'resources',
			'permissions.create_permission', 'permissions.update_permission', 'permissions.delete_permission',
			'permissions.create_permission_set', 'permissions.update_permission_set', 'permissions.delete_permission_set',
			'permissions.assign_permission', 'permissions.unassign_permission',
			'permissions.get_perm_sets', 'permissions.read_permissions', 'permissions.read_perm_sets',
			'tokens.create_token', 'tokens.validate_token', 'tokens.set_as_used',
			'authentication.read_user_events', 'authentication.create_auth_event'],
		_source := 'core');

	-- Service account permission sets
	perform unsecure.create_perm_set_as_system('Svc registrator permissions', true,
		_permissions := array ['users.register_user', 'users.add_to_default_groups', 'tokens.create_token'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Svc authenticator permissions', true,
		_permissions := array ['authentication.get_data', 'authentication.ensure_permissions',
			'authentication.get_users_groups_and_permissions', 'authentication.create_auth_event',
			'tokens.validate_token', 'tokens.set_as_used'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Svc token permissions', true,
		_permissions := array ['tokens.create_token', 'tokens.validate_token', 'tokens.set_as_used'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Svc api gateway permissions', true,
		_permissions := array ['api_keys.validate_api_key'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Svc group syncer permissions', true,
		_permissions := array ['groups.get_groups', 'groups.get_members', 'groups.create_member',
			'groups.delete_member', 'groups.get_mapping', 'users.register_user', 'users.add_to_default_groups'],
		_source := 'core');
	perform unsecure.create_perm_set_as_system('Svc data processor permissions', true,
		_source := 'core');

	-- Default groups
	perform unsecure.create_user_group_as_system('System admins', true, true);
	perform unsecure.assign_permission_as_system(1, null, 'system_admin');
	perform unsecure.create_user_group_as_system('Tenant admins', true, true);
	perform unsecure.assign_permission_as_system(2, null, 'tenant_admin');
	perform unsecure.create_user_group_as_system('Full admins', true, true);
	perform unsecure.assign_permission_as_system(3, null, 'full_admin');

	-- Providers
	perform auth.create_provider('initial', 1, null, 'email', 'Email authentication', false);
	perform auth.create_provider('initial', 1, null, 'aad', 'Azure authentication', false);
	perform auth.enable_provider('system', 1, null, 'aad');
	perform auth.enable_provider('system', 1, null, 'email');

	-- Set primary tenant as default
	update auth.tenant set is_default = true where tenant_id = 1;

end;
$$;

create or replace function auth.ensure_groups_and_permissions(_created_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _provider_code text, _provider_groups text[] DEFAULT NULL::text[], _provider_roles text[] DEFAULT NULL::text[])
    returns TABLE(__tenant_id integer, __tenant_uuid uuid, __groups text[], __permissions text[], __short_code_permissions text[])
    rows 1
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'authentication.ensure_permissions');

    update auth.user_identity
    set updated_by      = _created_by
      , updated_at      = now()
      , provider_groups = _provider_groups
      , provider_roles  = _provider_roles
    where provider_code = _provider_code
      and user_id = _target_user_id;

    create temporary table __temp_users_groups on commit drop as
    select ug.__tenant_id       as tenant_id
         , ug.__user_group_id   as user_group_id
         , ug.__user_group_code as user_group_code
    from unsecure.recalculate_user_groups(_created_by
             , _target_user_id
             , _provider_code
             ) ug;

    return query
        select up.__tenant_id
             , up.__tenant_uuid
             , up.__groups
             , up.__permissions
             , up.__short_code_permissions
        from unsecure.recalculate_user_permissions(_created_by
                 , _target_user_id, null) up;
end;
$$;

create or replace function auth.get_users_groups_and_permissions(_requested_by text, _user_id bigint, _correlation_id text, _target_user_id bigint)
    returns TABLE(__tenant_id integer, __tenant_uuid uuid, __groups text[], __permissions text[], __short_code_permissions text[])
    rows 1
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'authentication.get_users_groups_and_permissions');

    return query
        select up.__tenant_id
             , up.__tenant_uuid
             , up.__groups
             , up.__permissions
             , up.__short_code_permissions
        from unsecure.recalculate_user_permissions(_requested_by
                 , _target_user_id, null) up;
end;
$$;


create or replace function auth.get_user_assigned_permissions(_requested_by text, _user_id bigint, _correlation_id text, _target_user_id bigint, _tenant_id integer DEFAULT 1)
    returns TABLE(__permissions jsonb, __perm_set_title text, __perm_set_id integer, __perm_set_code text, __assignment_id bigint, __user_group_id integer)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'users.get_permissions', _tenant_id);

    return query select *
                 from unsecure.get_user_assigned_permissions(_requested_by, _user_id, _target_user_id, _tenant_id);

end;
$$;

create or replace function auth.search_permissions(
    _user_id bigint,
    _correlation_id text,
    _search_text text default null,
    _is_assignable boolean default null,
    _parent_code text default null,
    _page integer default 1,
    _page_size integer default 30,
    _tenant_id integer default 1,
    _source text default null
)
    returns TABLE(
        __permission_id integer,
        __title text,
        __code text,
        __full_code text,
        __short_code text,
        __is_assignable boolean,
        __has_children boolean,
        __source text,
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
    __parent_path ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'permissions.read_permissions', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 30), 100);

    if helpers.is_not_empty_string(_parent_code) then
        select node_path from auth.permission where full_code = _parent_code::ltree into __parent_path;
    end if;

    return query
        with filtered_permissions as (
            select p.permission_id
                 , count(*) over () as total_items
            from auth.permission p
            where (_is_assignable is null or p.is_assignable = _is_assignable)
              and (__parent_path is null or p.node_path <@ __parent_path)
              and (_source is null or p.source = _source)
              and (helpers.is_empty_string(__search_text)
                   or p.nrm_search_data like '%' || __search_text || '%')
            order by p.full_code
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select p.permission_id
             , p.title
             , p.code
             , p.full_code::text
             , p.short_code
             , p.is_assignable
             , p.has_children
             , p.source
             , fp.total_items
        from filtered_permissions fp
                 inner join auth.permission p on fp.permission_id = p.permission_id;
end;
$$;

create or replace function auth.search_perm_sets(
    _user_id bigint,
    _correlation_id text,
    _search_text text default null,
    _is_assignable boolean default null,
    _is_system boolean default null,
    _page integer default 1,
    _page_size integer default 30,
    _tenant_id integer default 1,
    _source text default null
)
    returns TABLE(
        __perm_set_id integer,
        __title text,
        __code text,
        __is_system boolean,
        __is_assignable boolean,
        __source text,
        __permission_count bigint,
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
    perform auth.has_permission(_user_id, _correlation_id, 'permissions.read_perm_sets', _tenant_id);

    __search_text := helpers.normalize_text(_search_text);

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 30), 100);

    return query
        with filtered_perm_sets as (
            select ps.perm_set_id
                 , count(*) over () as total_items
            from auth.perm_set ps
            where ps.tenant_id = _tenant_id
              and (_is_assignable is null or ps.is_assignable = _is_assignable)
              and (_is_system is null or ps.is_system = _is_system)
              and (_source is null or ps.source = _source)
              and (helpers.is_empty_string(__search_text)
                   or ps.nrm_search_data like '%' || __search_text || '%')
            order by ps.title
            offset ((_page - 1) * _page_size) limit _page_size
        ),
        permission_counts as (
            select psp.perm_set_id, count(psp.psp_id) as permission_count
            from auth.perm_set_perm psp
            where psp.perm_set_id in (select perm_set_id from filtered_perm_sets)
            group by psp.perm_set_id
        )
        select ps.perm_set_id
             , ps.title
             , ps.code
             , ps.is_system
             , ps.is_assignable
             , ps.source
             , coalesce(pc.permission_count, 0)
             , fps.total_items
        from filtered_perm_sets fps
                 inner join auth.perm_set ps on fps.perm_set_id = ps.perm_set_id
                 left join permission_counts pc on ps.perm_set_id = pc.perm_set_id;
end;
$$;

create or replace function public.get_permissions_map()
    returns TABLE(__permission_id integer, __full_code text, __short_code text, __title text, __source text)
    stable
    language sql
as
$$
    select permission_id, full_code::text, short_code, title, source
    from auth.permission
    where is_assignable = true
    order by full_code;
$$;

