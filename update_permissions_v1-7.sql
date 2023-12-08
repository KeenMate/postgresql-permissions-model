/*
 GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=0&v=1&c=c&f=ANSI%20Shadow&t=STAGE%20FUNCS

 SUB GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=1&v=1&c=c&f=Banner3&t=permissions

 */

select *
from start_version_update('1.7', E'Get user''s assigned groups', '',
													_component := 'keen_auth_permissions');

create or replace function auth.get_user_assigned_groups(_user_id bigint, _target_user_id bigint)
	returns table
					(
						__user_group_member_id            bigint,
						__user_group_id                   int,
						__user_group_code                 text,
						__user_group_title                text,
						__user_group_is_manually_assigned bool,
						__user_group_mapping_id           int
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
		select ugm.member_id, ugm.group_id, ug.code, ug.title, ugm.manual_assignment, ugm.mapping_id
		from auth.user_group_member ugm
					 inner join auth.user_group ug on ug.user_group_id = ugm.group_id
		where ugm.user_id = _target_user_id
		order by ug.title;

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
	or replace function auth.update_permission_data_v1_7()
	returns setof int
	language plpgsql
as
$$
declare
	__update_username text := 'auth_update_v1_7';
begin

	perform unsecure.create_permission_as_system('Read user group memberships', 'users');

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
from auth.update_permission_data_v1_7();

select *
from stop_version_update('1.7', _component := 'keen_auth_permissions');
