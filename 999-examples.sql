select *
from auth.enable_provider('system', 1, 'aad');
select *
from auth.enable_provider('system', 1, 'email');

select *
from auth.ensure_user_from_provider(_created_by := 'system', _user_id := 1, _provider_code := 'aad',
																		_provider_uid := '123456',
																		_username := 'ondrej.valenta@keenmate.com', _display_name := 'Ondrej Valenta',
																		_email := 'ondrej.valenta@keenmate.com', _user_data := null);

select *
from auth.ensure_user_from_provider(_created_by := 'system', _user_id := 1, _provider_code := 'aad',
																		_provider_uid := '456825',
																		_username := 'albert.moravec@keenmate.com', _display_name := 'Albert Moravec',
																		_email := 'albert.moravec@keenmate.com', _user_data := null);

select *
from auth.ensure_user_from_provider(_created_by := 'system', _user_id := 1, _provider_code := 'aad',
																		_provider_uid := '45682511',
																		_username := 'filip.jakab@keenmate.com', _display_name := 'Filip Jakab',
																		_email := 'filip.jakab@keenmate.com', _user_data := null);

select *
from auth.ensure_user_from_provider(_created_by := 'system', _user_id := 1, _provider_code := 'aad',
																		_provider_uid := '45682132123',
																		_username := 'jan.rada@keenmate.com', _display_name := 'Jan Rada',
																		_email := 'jan.rada@keenmate.com', _user_data := null);

select *
from auth.register_user('registrator', 1, 'lucie.novakova1@keenmate.com', '123456', _display_name := 'Lucie Novakova',
												_user_data := '{
													"firstName": "Lucie",
													"lastname": "Novakova"
												}');

select *
from auth.get_provider_users('system', 1, 'aad');

select *
from auth.get_provider_users('system', 1, 'email');

select *
from unsecure.create_user_group_member_as_system('ondrej.valenta@keenmate.com', 'Tenant admins', 1);

select *
from create_tenant('ondrej.valenta', 2, 'Albert Moravec', _tenant_owner_id := 3);

select *
from auth.create_owner('ondrej.valenta', 1, 4, 2, null);

select *
from auth.create_user_group('filip.jakab', 4, 'Our customers', 2);

-- albert.moravec, owner of the tenant, creates a new user group member (jan.rada)
select *
from auth.create_user_group_member('albert.moravec', 3, 2, 4, 5);

-- create tenant: Jan Rada, Account ondrej.valenta is not the owner, so the account has not permissions
select *
from create_tenant('ondrej.valenta', 2, 'Jan Rada');

-- assign tenant owner to user jan.rada as system account
select *
from create_owner('ondrej.valenta', 1, 5, 3);

-- jan.rada adds ondrej.valenta@keenmate.com as member of Tenant Owner of tenant: Jan Rada
select *
from auth.create_owner('jan.rada', 5, 2, 3);

-- create an external group with mapping to aad_rada in aad auth provider in tenant: Jan Rada
select *
from auth.create_external_user_group('system', 2, 3, 'External group 1', 'aad', _mapped_object_id := 'aad_rada');

-- create an external partners rule set with dummy permissions in tenant: Jan Rada
select *
from unsecure.create_perm_set_as_system('My external partners', 3, false, true,
																				array ['system.areas.public', 'system.areas.admin', 'system.manage_providers', 'system.manage_permissions.create_permission']);

-- remove incorrect permissions from My external partners permission set
select *
from auth.delete_perm_set_permissions('ondrej.valenta', 1::bigint, 3, 7,
																			array ['system.manage_providers', 'system.manage_permissions.create_permission']);

-- Add correct permissions to My external partners permission set
select *
from auth.add_perm_set_permissions('ondrej.valenta', 1::bigint, 3, 7,
																	 array ['system.manage_tenants.get_users']);

-- assign my_external_partners rule set to External group 1 in tenant: Jan Rada
select *
from unsecure.assign_permission_as_system(3, 9, null, 'my_external_partners');

-- imitate after login check for user: Jan Rada in tenant: Jan Rada with aad groups: [aad_rada]
-- creates a record in auth.user_permission_cache
select *
from auth.ensure_groups_and_permissions('authenticator', 1, 5, 3, 'aad', array ['aad_rada']);

-- check if user: Jan Rada has permission in tenant: Jan Rada has permission: system.manage_groups.create_group
-- checks if the record in auth.user_permission_cache is still valid and uses it or reevaluate everything and store it again for 15 seconds
select *
from auth.has_permission(3, 5, 'system.areas.public');
-- user permission check does not change for user: Jan Rada for 15 seconds and then on next check it is reevaluated
select *
from auth.user_permission_cache;

select *
from auth.get_tenant_users('system', 1, 3);

select *
from auth.get_tenant_groups('system', 1, 1);

select *
from user_group_members;

select *
from auth.disable_user('kerberos', 1, 6);

select *
from auth.enable_user('kerberos', 1, 6);

select *
from auth.lock_user('kerberos', 1, 6);

select *
from auth.unlock_user('kerberos', 1, 6);

select *
from auth.disable_user_identity('kerberos', 1, 6, 'email');

select *
from auth.enable_user_identity('kerberos', 1, 6, 'email');


select *
from auth.get_user_by_email_for_authentication(1, 'lucie.novakova1@keenmate.com');


select *
from auth.create_auth_event('authenticator', 1, 'email_verification', 6,
														'123.123.232.12', 'the best user agent there is',
														'domain.com');

select *
from auth.create_token('authenticator', 1, 2, 1, 'email_verification', 'email', '111jjjj2222jjjj333');

--4FDC32F629CE

select *
from auth.validate_token('authenticator', 1, null, '111jjjj2222jjjj333', '123.2.34.5', 'my agent', 'keenmate.com',
												 true);

select *
from auth.get_user_group_members('ondrej', 1, 3, 8);

select *
from auth.get_tenant_members('ondrej', 1, 3);

select *
from auth.get_tenant_groups('ondrej', 1, 3);


select *
from token;


select token_id, token_state_code
from auth.token
where token = '4FDC32F629CE'
	and ((null is not null and token.user_id = null) or true);



select *
from user_info;


select *
from permission_assignment pa
			 inner join effective_permissions ep on pa.perm_set_id = ep.perm_set_id
where group_id = 6;


select *
from create_user_group_as_system('');

select *
from add_journal_msg('ondrej', 1, 1
	, format('User %s assigned new owner: %s to tenant: %s'
											 , 'ondrej', 2, 2)
	, 'tenant', 2
	, array ['target_user_id', 2::text]
	, 50004);


select *
from auth.add_user_to_group('system',)


select *
from tenant;
select *
from user_info;
select *
from user_identity;
select *
from journal
where tenant_id = 2;

select *
from user_group ug
			 inner join public.user_group_member ugm on ug.user_group_id = ugm.group_id
			 inner join public.user_info ui on ugm.user_id = ui.user_id;

--
select *
from tenant;
-- select * from user_group;
-- select * from auth.perm_set;
-- select * from user_group_assignment;


select *
from has_permissions(1);

select *
from throw_no_permission(1, 2, 'system.a.b');
select *
from throw_no_permission(1, 2, array ['system.a.b', 'd.e.f'])

select *
from auth.create_user_group_member('System', 1, 1, 3, 2);

select *
from user_group_members;

select *
from auth.delete_user_group_member('system', 2, 1, 10, 2)