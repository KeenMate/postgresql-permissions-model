/*
 * Permission, Provider, Group & Perm Set Seeding
 * ================================================
 *
 * Moved from 029_seed_data.sql because create_permission now writes
 * to public.translation (created in 030). Must run after 030+045+046.
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Fix FK: user_group.tenant_id needs ON DELETE CASCADE for delete_tenant
do $$
begin
    if exists (
        select 1 from information_schema.table_constraints
        where constraint_name = 'user_group_tenant_id_fkey'
          and table_schema = 'auth' and table_name = 'user_group'
    ) then
        alter table auth.user_group drop constraint user_group_tenant_id_fkey;
        alter table auth.user_group add constraint user_group_tenant_id_fkey
            foreign key (tenant_id) references auth.tenant(tenant_id) on delete cascade;
    end if;
end $$;

-- Seed permissions, providers, groups, and perm sets
select auth.seed_permission_data();

-- Reset sequences to 1000 to reserve space for system tenants and groups
alter sequence auth.tenant_tenant_id_seq restart with 1000;
alter sequence auth.user_group_user_group_id_seq restart with 1000;

-- Backfill short_code for all permissions (in case any were created without it)
update auth.permission set short_code = unsecure.compute_short_code(permission_id)
where short_code is null;

-- Refresh MV after all seeds
select unsecure.refresh_translation_cache();

-- Assign service permission sets to service accounts
select * from unsecure.assign_permission_as_system(null::integer, 2, 'svc_registrator_permissions');
select * from unsecure.assign_permission_as_system(null::integer, 3, 'svc_authenticator_permissions');
select * from unsecure.assign_permission_as_system(null::integer, 4, 'svc_token_permissions');
select * from unsecure.assign_permission_as_system(null::integer, 5, 'svc_api_gateway_permissions');
select * from unsecure.assign_permission_as_system(null::integer, 6, 'svc_group_syncer_permissions');
select * from unsecure.assign_permission_as_system(null::integer, 800, 'svc_data_processor_permissions');
