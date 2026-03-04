/*
 * Auto-Lockout Functions
 * ======================
 *
 * - unsecure.check_and_auto_lock_user()  — counts recent failures, locks if threshold exceeded
 * - auth.record_login_failure()          — logs failure event, triggers auto-lock check
 *
 * Login flow (app layer):
 *   1. App calls auth.get_user_by_email_for_authentication(email) → user + password hash
 *   2. App verifies password hash
 *   3. If wrong → app calls auth.record_login_failure() → DB counts, maybe auto-locks
 *   4. If correct + MFA → app calls auth.create_mfa_challenge() → token
 *   5. User provides TOTP, app verifies, calls auth.verify_mfa_challenge()
 */

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
