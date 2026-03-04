/*
 * MFA Policy & Reset MFA — Schema, Seed Data, Error Function, Permissions
 * ========================================================================
 *
 * 1. auth.mfa_policy table (scope-based MFA enforcement rules)
 * 2. New event codes (mfa_policy_created, mfa_policy_deleted, mfa_recovery_reset)
 * 3. New error code & function (38007: mfa_policy_not_found)
 * 4. New permissions (mfa.reset_mfa, mfa.mfa_policy.*)
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ---------------------------------------------------------------------------
-- 1. auth.mfa_policy table
-- ---------------------------------------------------------------------------
-- Rules table for MFA enforcement. Resolution: user > group > tenant > global.
-- Null scope columns = broader scope. All nulls = global rule.
create table if not exists auth.mfa_policy (
    created_at     timestamp with time zone default now()           not null,
    created_by     text                     default 'unknown'::text not null,
    updated_at     timestamp with time zone default now()           not null,
    updated_by     text                     default 'unknown'::text not null,
    mfa_policy_id  bigint generated always as identity
        primary key,
    tenant_id      integer
        references auth.tenant
            on delete cascade,
    user_group_id  integer
        references auth.user_group
            on delete cascade,
    user_id        bigint
        references auth.user_info
            on delete cascade,
    mfa_required   boolean                  not null default true,
    constraint mfa_policy_created_by_check
        check (length(created_by) <= 250),
    constraint mfa_policy_updated_by_check
        check (length(updated_by) <= 250)
);

-- Unique constraint on scope tuple (coalesce handles nulls portably)
create unique index if not exists uq_mfa_policy_scope
    on auth.mfa_policy (coalesce(tenant_id, -1), coalesce(user_group_id, -1), coalesce(user_id, -1));

-- ---------------------------------------------------------------------------
-- 2. New event codes
-- ---------------------------------------------------------------------------
insert into const.event_code (event_id, code, category_code, title, description, is_system, source) values
    (10095, 'mfa_policy_created',  'user_event', 'MFA Policy Created',      'MFA policy rule was created', true, 'core'),
    (10096, 'mfa_policy_deleted',  'user_event', 'MFA Policy Deleted',      'MFA policy rule was deleted', true, 'core'),
    (10097, 'mfa_recovery_reset',  'user_event', 'MFA Recovery Codes Reset', 'MFA recovery codes were regenerated', true, 'core'),
    -- Error event code
    (38007, 'err_mfa_policy_not_found', 'mfa_error', 'MFA Policy Not Found', 'The specified MFA policy does not exist', true, 'core')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Error function: 38007
-- ---------------------------------------------------------------------------
create or replace function error.raise_38007(_mfa_policy_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA policy (id: %) does not exist', _mfa_policy_id
        using errcode = '38007';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. New permissions
-- ---------------------------------------------------------------------------
select * from unsecure.create_permission_as_system('Reset MFA', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('MFA Policy', 'mfa', false, null, 'core');
select * from unsecure.create_permission_as_system('Create MFA Policy', 'mfa.mfa_policy', true, null, 'core');
select * from unsecure.create_permission_as_system('Delete MFA Policy', 'mfa.mfa_policy', true, null, 'core');
select * from unsecure.create_permission_as_system('Get MFA Policies', 'mfa.mfa_policy', true, null, 'core');
