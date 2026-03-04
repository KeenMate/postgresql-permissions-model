/*
 * Auto-Lockout & MFA — Schema, Seed Data, Error Functions
 * ========================================================
 *
 * 1. pgcrypto extension (recovery code hashing)
 * 2. Missing 'invalid' token state
 * 3. const.mfa_type lookup table
 * 4. auth.user_mfa table
 * 5. Auto-lockout sys_param entries
 * 6. New event codes (user_auto_locked, mfa_*)
 * 7. New error codes & functions (38001-38006)
 * 8. New MFA permissions
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ---------------------------------------------------------------------------
-- 1. pgcrypto extension
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto schema ext;

-- ---------------------------------------------------------------------------
-- 2. Missing 'invalid' token state
-- ---------------------------------------------------------------------------
insert into const.token_state (code) values ('invalid') on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. MFA type lookup table
-- ---------------------------------------------------------------------------
create table if not exists const.mfa_type (
    code      text    primary key,
    title     text    not null,
    is_active boolean not null default true
);

insert into const.mfa_type (code, title) values
    ('totp', 'Time-based One-Time Password')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 4. auth.user_mfa table
-- ---------------------------------------------------------------------------
create table if not exists auth.user_mfa (
    created_at       timestamp with time zone default now()           not null,
    created_by       text                     default 'unknown'::text not null,
    updated_at       timestamp with time zone default now()           not null,
    updated_by       text                     default 'unknown'::text not null,
    user_mfa_id      bigint generated always as identity
        primary key,
    user_id          bigint                   not null
        references auth.user_info
            on delete cascade,
    mfa_type_code    text                     not null
        references const.mfa_type (code)
            on update cascade,
    secret_encrypted text                     not null,
    is_enabled       boolean                  not null default false,
    is_confirmed     boolean                  not null default false,
    recovery_codes   text[],
    enrolled_at      timestamp with time zone default now() not null,
    confirmed_at     timestamp with time zone,
    constraint user_mfa_created_by_check
        check (length(created_by) <= 250),
    constraint user_mfa_updated_by_check
        check (length(updated_by) <= 250),
    constraint uq_user_mfa_user_type
        unique (user_id, mfa_type_code)
);

-- ---------------------------------------------------------------------------
-- 5. Auto-lockout system parameters
-- ---------------------------------------------------------------------------
insert into const.sys_param (group_code, code, text_value, number_value) values
    ('login_lockout', 'max_failed_attempts', '5', 5),
    ('login_lockout', 'window_minutes', '15', 15)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 6. New event categories & codes
-- ---------------------------------------------------------------------------
insert into const.event_category (category_code, title, range_start, range_end, is_error, source) values
    ('mfa_error', 'MFA Errors', 38001, 38999, true, 'core')
on conflict do nothing;

insert into const.event_code (event_id, code, category_code, title, description, is_system, source) values
    -- Auto-lockout (user_event range)
    (10083, 'user_auto_locked',           'user_event', 'User Auto-Locked',           'User account was auto-locked after too many failed login attempts', true, 'core'),
    -- MFA informational events (user_event range)
    (10090, 'mfa_enrolled',               'user_event', 'MFA Enrolled',               'MFA enrollment was initiated', true, 'core'),
    (10091, 'mfa_enrollment_confirmed',   'user_event', 'MFA Enrollment Confirmed',   'MFA enrollment was confirmed with a valid code', true, 'core'),
    (10092, 'mfa_challenge_created',      'user_event', 'MFA Challenge Created',      'MFA challenge token was created', true, 'core'),
    (10093, 'mfa_challenge_passed',       'user_event', 'MFA Challenge Passed',       'MFA challenge was successfully verified', true, 'core'),
    (10094, 'mfa_recovery_used',          'user_event', 'MFA Recovery Code Used',     'MFA recovery code was used to pass challenge', true, 'core'),
    -- MFA errors (38001-38999)
    (38001, 'err_mfa_already_enrolled',   'mfa_error', 'MFA Already Enrolled',       'MFA is already enrolled and confirmed for this type', true, 'core'),
    (38002, 'err_mfa_not_enrolled',       'mfa_error', 'MFA Not Enrolled',           'MFA is not enrolled for this type', true, 'core'),
    (38003, 'err_mfa_not_confirmed',      'mfa_error', 'MFA Not Confirmed',          'MFA enrollment has not been confirmed yet', true, 'core'),
    (38004, 'err_mfa_invalid_code',       'mfa_error', 'MFA Invalid Code',           'The provided MFA code is not valid', true, 'core'),
    (38005, 'err_mfa_required',           'mfa_error', 'MFA Required',               'MFA verification is required to complete this action', true, 'core'),
    (38006, 'err_mfa_type_not_found',     'mfa_error', 'MFA Type Not Found',         'The specified MFA type does not exist or is inactive', true, 'core')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 7. Error functions (38001-38006)
-- ---------------------------------------------------------------------------
create or replace function error.raise_38001(_user_id bigint, _mfa_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA (type: %) is already enrolled and confirmed for user (id: %)', _mfa_type_code, _user_id
        using errcode = '38001';
end;
$$;

create or replace function error.raise_38002(_user_id bigint, _mfa_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA (type: %) is not enrolled for user (id: %)', _mfa_type_code, _user_id
        using errcode = '38002';
end;
$$;

create or replace function error.raise_38003(_user_id bigint, _mfa_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA (type: %) enrollment is not confirmed for user (id: %)', _mfa_type_code, _user_id
        using errcode = '38003';
end;
$$;

create or replace function error.raise_38004() returns void
    language plpgsql
as
$$
begin
    raise exception 'The provided MFA code is not valid'
        using errcode = '38004';
end;
$$;

create or replace function error.raise_38005(_user_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA verification is required for user (id: %)', _user_id
        using errcode = '38005';
end;
$$;

create or replace function error.raise_38006(_mfa_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'MFA type (code: %) does not exist or is inactive', _mfa_type_code
        using errcode = '38006';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. MFA permissions
-- ---------------------------------------------------------------------------
select * from unsecure.create_permission_as_system('MFA', '', false, null, 'core');
select * from unsecure.create_permission_as_system('Enroll MFA', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('Confirm MFA Enrollment', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('Disable MFA', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('Get MFA Status', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('Create MFA Challenge', 'mfa', true, null, 'core');
select * from unsecure.create_permission_as_system('Verify MFA Challenge', 'mfa', true, null, 'core');
