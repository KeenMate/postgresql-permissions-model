/*
 GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=0&v=1&c=c&f=ANSI%20Shadow&t=STAGE%20FUNCS

 SUB GROUP HEADERS GENERATED BY: https://patorjk.com/software/taag/#p=display&h=1&v=1&c=c&f=Banner3&t=permissions

 */


select *
from check_version('1.10', _component := 'keen_auth_permissions', _throw_err := true);

select *
from start_version_update('1.11',
													'Fix of unsecure.assign_permissions and incorrectly assigned permissions',
													_component := 'keen_auth_permissions');


/***
 *    ███████╗██╗██╗  ██╗███████╗███████╗
 *    ██╔════╝██║╚██╗██╔╝██╔════╝██╔════╝
 *    █████╗  ██║ ╚███╔╝ █████╗  ███████╗
 *    ██╔══╝  ██║ ██╔██╗ ██╔══╝  ╚════██║
 *    ██║     ██║██╔╝ ██╗███████╗███████║
 *    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝
 *
 */

create unique index uq_auth_permission_assignment_tenant_user on auth.permission_assignment (tenant_id, user_id,
																																														 coalesce(perm_set_id, 0),
																																														 coalesce(permission_id, 0));
create unique index uq_auth_permission_assignment_tenant_group on auth.permission_assignment (tenant_id, group_id,
																																														 coalesce(perm_set_id, 0),
																																														 coalesce(permission_id, 0));


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
from stop_version_update('1.11', _component := 'keen_auth_permissions');
