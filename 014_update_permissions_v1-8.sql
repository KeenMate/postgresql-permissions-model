/*
 GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=0&v=1&c=c&f=ANSI%20Shadow&t=STAGE%20FUNCS

 SUB GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=1&v=1&c=c&f=Banner3&t=permissions

 */

select *
from start_version_update('1.8', E'Sync of external group members', '',
													_component := 'keen_auth_permissions');

-- replacement of user_group.manual_assignment

create table const.user_group_member_type
(
	code text not null primary key
);

insert into const.user_group_member_type(code)
values ('manual'),
			 ('sync'),
			 ('adhoc');

alter table auth.user_group_member
	add column member_type_code text not null default 'manual' references const.user_group_member_type (code) on delete cascade;

drop view auth.user_group_members;
create view auth.user_group_members as
(
select ug.tenant_id
		 , ugm.member_id
		 , case when t.code is null then 'system' else t.code end                             as tenant_code
		 , ui.user_id
		 , ui.display_name                                                                    as user_display_name
		 , ui.uuid                                                                            as user_uuid
		 , ui.code                                                                            as user_code
		 , ug.user_group_id
		 , ug.is_external
		 , ug.is_active
		 , ug.is_assignable
		 , ug.title                                                                           as group_title
		 , ug.code                                                                            as group_code
		 , case when ugm.mapping_id is not null then 'mapped_member' else 'direct_member' end as member_type
		 , ugm.member_type_code
		 , u.mapped_object_name
		 , u.mapped_role
from auth.user_group ug
			 left join auth.user_group_member ugm on ugm.group_id = ug.user_group_id
			 left join auth.user_info ui
								 on ui.user_id = ugm.user_id
			 inner join auth.tenant t on ug.tenant_id = t.tenant_id
			 left join auth.user_group_mapping u on ugm.mapping_id = u.ug_mapping_id
	);

create
	or replace function unsecure.recalculate_user_groups(_created_by text,
																											 _target_user_id bigint, _provider_code text)
	returns table
					(
						__groups text[]
					)
	language plpgsql
as
$$
declare
	__not_really_used int;
	__provider_groups text[];
	__provider_roles  text[];
begin

	select provider_groups, provider_roles
	from auth.user_identity
	where provider_code = _provider_code
		and user_id = _target_user_id
	into __provider_groups, __provider_roles;

-- cleanup membership of groups user is no longer part of
	with affected_deleted_group_tenants as (
		delete
			from auth.user_group_member
				where user_id = _target_user_id
					and mapping_id is not null
					and group_id not in (select distinct ugm.group_id
															 from unnest(__provider_groups) g
																			inner join auth.user_group_mapping ugm
																								 on ugm.provider_code = _provider_code and ugm.mapped_object_id = lower(g)
																			inner join auth.user_group u
																								 on u.user_group_id = ugm.group_id
															 union
															 select distinct ugm.group_id
															 from unnest(__provider_roles) r
																			inner join auth.user_group_mapping ugm
																								 on ugm.provider_code = _provider_code and ugm.mapped_role = lower(r)
																			inner join auth.user_group u
																								 on u.user_group_id = ugm.group_id)
				returning group_id)
		 , affected_group_tenants as (
		insert
			into auth.user_group_member (created_by, user_id, group_id, mapping_id, member_type_code)
				select distinct _created_by, _target_user_id, ugm.group_id, ugm.ug_mapping_id, 'adhoc'
				from unnest(__provider_groups) g
							 inner join auth.user_group_mapping ugm
													on ugm.provider_code = _provider_code and ugm.mapped_object_id = lower(g)
				where ugm.group_id not in (select group_id from auth.user_group_member where user_id = _target_user_id)
				returning group_id)
		 , affected_role_tenants as (
		insert
			into auth.user_group_member (created_by, user_id, group_id, mapping_id, member_type_code)
				select distinct _created_by, _target_user_id, ugm.group_id, ugm.ug_mapping_id, 'adhoc'
				from unnest(__provider_roles) r
							 inner join auth.user_group_mapping ugm
													on ugm.provider_code = _provider_code and ugm.mapped_role = lower(r)
				where ugm.group_id not in (select group_id from auth.user_group_member where user_id = _target_user_id)
				returning group_id)
		 , all_group_ids as (select group_id
												 from affected_deleted_group_tenants
												 union
												 select group_id
												 from affected_group_tenants
												 union
												 select group_id
												 from affected_role_tenants)
		 , all_tenants as (select tenant_id
											 from all_group_ids ids
															inner join auth.user_group ug
																				 on ids.group_id = ug.user_group_id
											 group by tenant_id)
-- variable not really used, it's there just to avoid 'query has no destination for result data'
	select at.tenant_id
	from all_tenants at
		 , lateral unsecure.clear_permission_cache(_created_by, _target_user_id, at.tenant_id) r
	into __not_really_used;

	return query
		select array_agg(distinct ug.code)
		from auth.user_group_member ugm
					 inner join auth.user_group ug on ug.user_group_id = ugm.group_id
		where user_id = _target_user_id;
end;
$$;

drop function unsecure.create_user_group_member(_created_by text, _user_id bigint,
																								_user_group_id int,
																								_target_user_id bigint, _tenant_id int);
create function unsecure.create_user_group_member(_created_by text, _user_id bigint,
																									_user_group_id int,
																									_target_user_id bigint, _tenant_id int default 1)
	returns table
					(
						__user_group_member_id bigint
					)
	language plpgsql
	rows 1
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

	return query insert into auth.user_group_member (created_by, group_id, user_id, member_type_code)
		values (_created_by, _user_group_id, _target_user_id, 'manual')
		returning member_id;

	perform
		add_journal_msg_jsonb(_created_by, _user_id
			, format('User group: (code: %s) member: (upn: %s) in tenant: %s created by: %s'
														, __user_group_code, __user_upn, _tenant_id, _created_by)
			, 'group', _user_group_id
			, jsonb_build_object('target_user_id', _target_user_id)
			, 50131
			, _tenant_id := _tenant_id);
end;
$$;

create or replace function auth.delete_user_group_member(_deleted_by text, _user_id bigint, _user_group_id integer, _target_user_id bigint,
																												 _tenant_id integer default 1) returns void
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


	perform
		add_journal_msg(_deleted_by, _user_id
			, format('User group: (code: %s) member: (upn: %s) in tenant: %s deleted by: %s'
											, __user_group_code, __user_upn, _tenant_id, _deleted_by)
			, 'group', _user_group_id
			, array ['target_user_id', _target_user_id::text]
			, 50133
			, _tenant_id := _tenant_id);
end;
$$;



drop function unsecure.get_user_group_members(_requested_by text, _user_id bigint, _user_group_id int, _tenant_id int);
create function unsecure.get_user_group_members(_requested_by text, _user_id bigint,
																								_user_group_id int, _tenant_id int default 1)
	returns table
					(
						__created                    timestamptz,
						__created_by                 text,
						__member_id                  bigint,
						__member_type_code           text,
						__user_id                    bigint,
						__user_display_name          text,
						__user_is_system             bool,
						__user_is_active             bool,
						__user_is_locked             bool,
						__mapping_id                 int,
						__mapping_mapped_object_name text,
						__mapping_provider_code      text
					)
	language plpgsql
	rows 1
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
		select ugm.created
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
					 left join auth.user_group_mapping ugma on ugma.ug_mapping_id = ugm.mapping_id
					 inner join auth.user_info ui on ui.user_id = ugm.user_id
		where ugm.group_id = _user_group_id;

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

drop function auth.get_user_group_members(_requested_by text, _user_id bigint, _user_group_id int, _tenant_id int);
create function auth.get_user_group_members(_requested_by text, _user_id bigint,
																						_user_group_id int, _tenant_id int default 1)
	returns table
					(
						__created                    timestamptz,
						__created_by                 text,
						__member_id                  bigint,
						__member_type_code           text,
						__user_id                    bigint,
						__user_display_name          text,
						__user_is_system             bool,
						__user_is_active             bool,
						__user_is_locked             bool,
						__mapping_id                 int,
						__mapping_mapped_object_name text,
						__mapping_provider_code      text
					)
	language plpgsql
	rows 1
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


drop function auth.set_user_group_as_external(_modified_by text, _user_id bigint, _user_group_id int, _tenant_id int);
create function auth.set_user_group_as_external(_modified_by text, _user_id bigint, _user_group_id int,
																								_tenant_id int default 1)
	returns void
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
	set modified    = now()
		, modified_by = _modified_by
		, is_external = true
	where user_group_id = _user_group_id
	returning code
		into __user_group_code;


	perform
		add_journal_msg(_modified_by, _user_id
			, format('User group: (code: %s) set as external in tenant: %s by: %s'
											, __user_group_code, _tenant_id, _modified_by)
			, 'group', _user_group_id
			, _data_object_code := __user_group_code
			, _payload := null
			, _event_id := 50208
			, _tenant_id := _tenant_id);
end;
$$;

drop function if exists auth.get_user_assigned_groups(_user_id bigint, _target_user_id bigint);
create or replace function auth.get_user_assigned_groups(_user_id bigint, _target_user_id bigint)
	returns table
					(
						__user_group_member_id        bigint,
						__user_group_id               int,
						__user_group_code             text,
						__user_group_title            text,
						__user_group_member_type_code text,
						__user_group_mapping_id       int
					)
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

update auth.user_group_member
set member_type_code = case when manual_assignment then 'manual' else 'adhoc' end
where true;

alter table auth.user_group_member
	drop column manual_assignment;

create table stage.external_group_member
(
	external_group_member_id bigint generated always as identity primary key,
	user_group_id            integer not null references auth.user_group (user_group_id) on delete cascade,
	user_group_mapping_id    integer not null references auth.user_group_mapping (ug_mapping_id) on delete cascade,
	member_upn               text    not null,
	member_display_name      text    not null,
	member_email             text
) inherits (_template_created);

create unique index uq_external_group_member on stage.external_group_member (user_group_mapping_id, member_upn);

alter table auth.user_group
	add column is_synced bool not null default false
		constraint must_be_external check ( not is_synced or (is_synced = true and is_external = true));

alter table auth.user_group
	add column create_missing_users_on_sync bool not null default false
		constraint must_be_synced check ( not create_missing_users_on_sync or
																			(create_missing_users_on_sync = true and is_synced = true));


create or replace function auth.get_user_groups_to_sync(_user_id bigint)
	returns table
					(
						__user_group_id         integer,
						__user_group_mapping_id integer,
						__title                 text,
						__code                  text,
						__provider_code         text,
						__mapped_object_id      text,
						__mapped_object_name    text
					)
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
	returns table
					(
						__user_group_id         int,
						__user_group_mapping_id int,
						__state_code            text,
						__user_id               bigint,
						__upn                   text
					)
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

create or replace function auth.process_external_group_member_sync(_run_by text, _user_id bigint, _user_group_id int default null)
	returns table
					(
						__user_group_id         int,
						__user_group_mapping_id int,
						__state_code            text,
						__user_id               bigint,
						__upn                   text
					)
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


/***
 *    ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗    ██████╗  █████╗ ████████╗ █████╗
 *    ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝    ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗
 *    ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗      ██║  ██║███████║   ██║   ███████║
 *    ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝      ██║  ██║██╔══██║   ██║   ██╔══██║
 *    ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗    ██████╔╝██║  ██║   ██║   ██║  ██║
 *     ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
 *
 */

create
	or replace function auth.update_permission_data_v1_8()
	returns setof int
	language plpgsql
as
$$
declare
	__update_username text := 'auth_update_v1_8';
begin

	-- 	perform unsecure.create_permission_as_system('Read user group memberships', 'users');

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
from auth.update_permission_data_v1_8();

select *
from stop_version_update('1.8', _component := 'keen_auth_permissions');
