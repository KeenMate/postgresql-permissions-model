/*
 * Auto-Lockout Functions
 * ======================
 *
 * - unsecure.check_and_auto_lock_user()  — counts recent failures, locks if threshold exceeded
 * - auth.record_login_failure()          — logs failure event, triggers auto-lock check
 * - auth.verify_user_by_email()          — single-call email/password login: verify hash, record failure + auto-lockout on mismatch, return user on success
 *
 * Login flow (app layer):
 *   Option A — Two-step (existing):
 *     1. App calls auth.get_user_by_email_for_authentication(email) → user + password hash
 *     2. App verifies password hash
 *     3. If wrong → app calls auth.record_login_failure() → DB counts, maybe auto-locks
 *     4. If correct + MFA → app calls auth.create_mfa_challenge() → token
 *     5. User provides TOTP, app verifies, calls auth.verify_mfa_challenge()
 *
 *   Option B — Single-call (new):
 *     1. App hashes password, calls auth.verify_user_by_email(email, hash) → user data or error
 *     2. If correct + MFA → app calls auth.create_mfa_challenge() → token
 *     3. User provides TOTP, app verifies, calls auth.verify_mfa_challenge()
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ---------------------------------------------------------------------------
-- unsecure.check_and_auto_lock_user
-- ---------------------------------------------------------------------------
-- Checks recent login failures for a user and auto-locks if threshold exceeded.
-- Returns true if the user was locked by this call, false otherwise.
-- ---------------------------------------------------------------------------
create or replace function unsecure.check_and_auto_lock_user(
    _updated_by      text,
    _correlation_id  text,
    _target_user_id  bigint,
    _request_context jsonb default null
) returns boolean
    language plpgsql
as
$$
declare
    __max_attempts   int;
    __window_minutes int;
    __failure_count  bigint;
    __is_locked      boolean;
begin
    -- Read lockout parameters (with hardcoded fallback defaults)
    select coalesce(sp.number_value, 5)
    from const.sys_param sp
    where sp.group_code = 'login_lockout'
      and sp.code = 'max_failed_attempts'
    into __max_attempts;

    if __max_attempts is null then
        __max_attempts := 5;
    end if;

    select coalesce(sp.number_value, 15)
    from const.sys_param sp
    where sp.group_code = 'login_lockout'
      and sp.code = 'window_minutes'
    into __window_minutes;

    if __window_minutes is null then
        __window_minutes := 15;
    end if;

    -- Skip if user is already locked
    select ui.is_locked
    from auth.user_info ui
    where ui.user_id = _target_user_id
    into __is_locked;

    if __is_locked then
        return false;
    end if;

    -- Count recent login and MFA failures within the window
    select count(*)
    from auth.user_event ue
    where ue.target_user_id = _target_user_id
      and ue.event_type_code in ('user_login_failed', 'mfa_challenge_failed')
      and ue.created_at >= now() - make_interval(mins => __window_minutes)
    into __failure_count;

    -- If threshold exceeded, lock the user
    if __failure_count >= __max_attempts then
        update auth.user_info
        set is_locked   = true,
            updated_at  = now(),
            updated_by  = _updated_by
        where user_id = _target_user_id;

        -- Clear permission cache for locked user
        perform unsecure.clear_permission_cache(_updated_by, _target_user_id);

        -- Log auto-lock event
        perform unsecure.create_user_event(
            _updated_by, null, _correlation_id, 'user_auto_locked',
            _target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object(
                'failure_count', __failure_count,
                'window_minutes', __window_minutes,
                'max_attempts', __max_attempts
            )
        );

        return true;
    end if;

    return false;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.record_login_failure
-- ---------------------------------------------------------------------------
-- Called by the app after password hash mismatch. The DB never sees raw passwords.
-- Logs the failure event, then checks auto-lock. Raises appropriate error:
--   - If auto-locked: raises 33004 (user locked)
--   - Otherwise: raises 52103 (invalid credentials / user not found)
-- ---------------------------------------------------------------------------
create or replace function auth.record_login_failure(
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _email           text,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
declare
    __auto_locked boolean;
begin
    -- Permission check (same as get_user_by_email_for_authentication)
    perform
        auth.has_permission(_user_id, _correlation_id, 'authentication.get_data');

    -- Log the login failure event
    perform unsecure.create_user_event(
        'system', _user_id, _correlation_id, 'user_login_failed',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object(
            'email', lower(trim(_email)),
            'provider', 'email',
            'reason', 'wrong_password'
        )
    );

    -- Check and possibly auto-lock
    __auto_locked := unsecure.check_and_auto_lock_user(
        'system', _correlation_id, _target_user_id, _request_context
    );

    -- Raise appropriate error
    if __auto_locked then
        perform error.raise_33004(_target_user_id);
    else
        perform error.raise_52103(null, _email);
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.verify_user_by_email
-- ---------------------------------------------------------------------------
-- Single-call email/password login: looks up user by email, validates status,
-- compares password hash, and returns user data on success.
-- On hash mismatch: logs failure event, triggers auto-lockout check.
--   - If auto-locked: raises 33004 (user locked)
--   - Otherwise: raises 52103 (invalid credentials)
-- Unlike get_user_by_email_for_authentication, this function only logs
-- user_logged_in AFTER a confirmed hash match (cleaner audit trail).
-- ---------------------------------------------------------------------------
create or replace function auth.verify_user_by_email(
    _user_id         bigint,
    _correlation_id  text,
    _email           text,
    _password_hash   text,
    _request_context jsonb default null
) returns table (
    __user_id      bigint,
    __code         text,
    __uuid         text,
    __username     text,
    __email        text,
    __display_name text
)
    language plpgsql
as
$$
declare
    __target_user_id     bigint;
    __target_uid_id      bigint;
    __normalized_email   text;
    __is_active          bool;
    __is_locked          bool;
    __is_identity_active bool;
    __can_login          bool;
    __stored_hash        text;
    __auto_locked        boolean;
begin
    -- Permission check
    perform
        auth.has_permission(_user_id, _correlation_id, 'authentication.get_data');

    -- Validate email provider is active
    perform
        auth.validate_provider_is_active('email');

    __normalized_email := lower(trim(_email));

    -- Lookup user via email identity
    select ui.user_id, uid.user_identity_id, ui.is_active, ui.is_locked, uid.is_active, ui.can_login, uid.password_hash
    from auth.user_identity uid
        inner join auth.user_info ui on uid.user_id = ui.user_id
    where uid.provider_code = 'email'
        and uid.uid = __normalized_email
    into __target_user_id, __target_uid_id, __is_active, __is_locked, __is_identity_active, __can_login, __stored_hash;

    -- Status validation (same order as get_user_by_email_for_authentication)

    -- 1. User not found
    if __is_active is null then
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            null,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_not_found'));
        perform error.raise_52103(null, __normalized_email);
    end if;

    -- 2. Login disabled
    if not __can_login then
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            __target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'login_disabled'));
        perform error.raise_52112(__target_user_id);
    end if;

    -- 3. User disabled
    if not __is_active then
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            __target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_disabled'));
        perform error.raise_52105(__target_user_id);
    end if;

    -- 4. Identity disabled
    if not __is_identity_active then
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            __target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'identity_disabled'));
        perform error.raise_52110(__target_user_id, 'email');
    end if;

    -- 5. User locked
    if __is_locked then
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            __target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'user_locked'));
        perform error.raise_52106(__normalized_email);
    end if;

    -- 6. Compare password hashes
    if __stored_hash is distinct from _password_hash then
        -- Log failure
        perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_login_failed',
            __target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email', 'reason', 'wrong_password'));

        -- Check auto-lockout
        __auto_locked := unsecure.check_and_auto_lock_user(
            'system', _correlation_id, __target_user_id, _request_context
        );

        if __auto_locked then
            perform error.raise_33004(__normalized_email);
        else
            perform error.raise_52103(null, __normalized_email);
        end if;
    end if;

    -- 7. Hash matches — update last used provider
    perform
        unsecure.update_last_used_provider(__target_user_id, 'email');

    -- 8. Log successful login (only after confirmed hash match)
    perform unsecure.create_user_event('system', _user_id, _correlation_id, 'user_logged_in',
        __target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('email', __normalized_email, 'provider', 'email'));

    -- 9. Return user data (no hash/salt — app doesn't need them)
    return query
        select ui.user_id
             , ui.code
             , ui.uuid::text
             , ui.username
             , ui.email
             , ui.display_name
        from auth.user_identity uid
            inner join auth.user_info ui on uid.user_id = ui.user_id
        where uid.provider_code = 'email'
            and uid.uid = __normalized_email;
end;
$$;
