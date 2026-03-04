/*
 * MFA Functions
 * =============
 *
 * - auth.enroll_mfa()              — initiate TOTP enrollment (two-step: enroll → confirm)
 * - auth.confirm_mfa_enrollment()  — confirm enrollment with a valid TOTP code
 * - auth.disable_mfa()             — remove MFA for a user
 * - auth.get_mfa_status()          — check MFA enrollment/confirmation state
 * - auth.create_mfa_challenge()    — create a time-limited MFA challenge token
 * - auth.verify_mfa_challenge()    — verify TOTP code or recovery code against challenge
 */

-- ---------------------------------------------------------------------------
-- auth.enroll_mfa
-- ---------------------------------------------------------------------------
-- Initiates MFA enrollment. App provides the encrypted TOTP secret (DB never
-- sees the raw secret). Generates 10 recovery codes (returned plaintext once,
-- stored as SHA-256 hashes).
--
-- If the user already has a confirmed enrollment for this type, raises 38001.
-- If there is an unconfirmed pending enrollment, it is replaced.
-- ---------------------------------------------------------------------------
create or replace function auth.enroll_mfa(
    _created_by       text,
    _user_id          bigint,
    _correlation_id   text,
    _target_user_id   bigint,
    _mfa_type_code    text,
    _secret_encrypted text,
    _request_context  jsonb default null
) returns table (
    __user_mfa_id    bigint,
    __mfa_type_code  text,
    __recovery_codes text[],
    __enrolled_at    timestamp with time zone
)
    language plpgsql
as
$$
declare
    __existing_confirmed boolean;
    __plain_codes        text[];
    __hashed_codes       text[];
    __code               text;
    __last_item          auth.user_mfa;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.enroll_mfa');

    -- Validate MFA type exists and is active
    if not exists (select 1 from const.mfa_type where code = _mfa_type_code and is_active) then
        perform error.raise_38006(_mfa_type_code);
    end if;

    -- Check for existing confirmed enrollment
    select um.is_confirmed
    from auth.user_mfa um
    where um.user_id = _target_user_id
      and um.mfa_type_code = _mfa_type_code
    into __existing_confirmed;

    if __existing_confirmed is true then
        perform error.raise_38001(_target_user_id, _mfa_type_code);
    end if;

    -- Delete any unconfirmed pending enrollment
    delete from auth.user_mfa
    where user_id = _target_user_id
      and mfa_type_code = _mfa_type_code
      and is_confirmed = false;

    -- Generate 10 recovery codes
    __plain_codes := array[]::text[];
    __hashed_codes := array[]::text[];
    for _i in 1..10 loop
        __code := helpers.random_string(20);
        __plain_codes := array_append(__plain_codes, __code);
        __hashed_codes := array_append(__hashed_codes, encode(ext.digest(__code, 'sha256'), 'hex'));
    end loop;

    -- Insert new enrollment
    insert into auth.user_mfa (created_by, updated_by, user_id, mfa_type_code, secret_encrypted,
                               is_enabled, is_confirmed, recovery_codes, enrolled_at)
    values (_created_by, _created_by, _target_user_id, _mfa_type_code, _secret_encrypted,
            false, false, __hashed_codes, now())
    returning *
        into __last_item;

    -- Log enrollment event
    perform unsecure.create_user_event(
        _created_by, _user_id, _correlation_id, 'mfa_enrolled',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('mfa_type', _mfa_type_code, 'user_mfa_id', __last_item.user_mfa_id)
    );

    return query
        select __last_item.user_mfa_id, __last_item.mfa_type_code, __plain_codes, __last_item.enrolled_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.confirm_mfa_enrollment
-- ---------------------------------------------------------------------------
-- Confirms MFA enrollment. The app verifies the TOTP code externally and
-- passes _code_is_valid = true. If invalid, raises 38004.
-- ---------------------------------------------------------------------------
create or replace function auth.confirm_mfa_enrollment(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _mfa_type_code   text,
    _code_is_valid   boolean,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
declare
    __user_mfa_id bigint;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.confirm_mfa_enrollment');

    -- Verify enrollment exists and is pending
    select um.user_mfa_id
    from auth.user_mfa um
    where um.user_id = _target_user_id
      and um.mfa_type_code = _mfa_type_code
      and um.is_confirmed = false
    into __user_mfa_id;

    if __user_mfa_id is null then
        perform error.raise_38002(_target_user_id, _mfa_type_code);
    end if;

    -- Check if app says code is valid
    if not _code_is_valid then
        perform error.raise_38004();
    end if;

    -- Confirm the enrollment
    update auth.user_mfa
    set is_enabled    = true,
        is_confirmed  = true,
        confirmed_at  = now(),
        updated_at    = now(),
        updated_by    = _updated_by
    where user_mfa_id = __user_mfa_id;

    -- Log confirmation event
    perform unsecure.create_user_event(
        _updated_by, _user_id, _correlation_id, 'mfa_enrollment_confirmed',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('mfa_type', _mfa_type_code, 'user_mfa_id', __user_mfa_id)
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.disable_mfa
-- ---------------------------------------------------------------------------
-- Removes MFA enrollment entirely. Logs mfa_disabled event (existing code 10051).
-- ---------------------------------------------------------------------------
create or replace function auth.disable_mfa(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _mfa_type_code   text,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
declare
    __user_mfa_id bigint;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.disable_mfa');

    -- Verify enrollment exists
    select um.user_mfa_id
    from auth.user_mfa um
    where um.user_id = _target_user_id
      and um.mfa_type_code = _mfa_type_code
    into __user_mfa_id;

    if __user_mfa_id is null then
        perform error.raise_38002(_target_user_id, _mfa_type_code);
    end if;

    -- Delete the enrollment
    delete from auth.user_mfa
    where user_mfa_id = __user_mfa_id;

    -- Log disable event (existing event code 10051: mfa_disabled)
    perform unsecure.create_user_event(
        _updated_by, _user_id, _correlation_id, 'mfa_disabled',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('mfa_type', _mfa_type_code, 'user_mfa_id', __user_mfa_id)
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.get_mfa_status
-- ---------------------------------------------------------------------------
-- Returns MFA enrollment status for a user. Returns empty set if not enrolled.
-- ---------------------------------------------------------------------------
create or replace function auth.get_mfa_status(
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint
) returns table (
    __user_mfa_id             bigint,
    __mfa_type_code           text,
    __is_enabled              boolean,
    __is_confirmed            boolean,
    __enrolled_at             timestamp with time zone,
    __confirmed_at            timestamp with time zone,
    __recovery_codes_remaining int
)
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.get_mfa_status');

    return query
        select um.user_mfa_id,
               um.mfa_type_code,
               um.is_enabled,
               um.is_confirmed,
               um.enrolled_at,
               um.confirmed_at,
               coalesce(array_length(um.recovery_codes, 1), 0)
        from auth.user_mfa um
        where um.user_id = _target_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.create_mfa_challenge
-- ---------------------------------------------------------------------------
-- Creates a time-limited MFA challenge token. Invalidates any previous valid
-- MFA tokens for the user. Returns token UID and expiry.
-- ---------------------------------------------------------------------------
create or replace function auth.create_mfa_challenge(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _mfa_type_code   text,
    _request_context jsonb default null
) returns table (
    __token_uid  text,
    __expires_at timestamp with time zone
)
    language plpgsql
as
$$
declare
    __user_mfa_id     bigint;
    __is_confirmed    boolean;
    __is_enabled      boolean;
    __token_record    record;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.create_mfa_challenge');

    -- Validate MFA is enrolled, confirmed, and enabled
    select um.user_mfa_id, um.is_confirmed, um.is_enabled
    from auth.user_mfa um
    where um.user_id = _target_user_id
      and um.mfa_type_code = _mfa_type_code
    into __user_mfa_id, __is_confirmed, __is_enabled;

    if __user_mfa_id is null then
        perform error.raise_38002(_target_user_id, _mfa_type_code);
    end if;

    if not __is_confirmed then
        perform error.raise_38003(_target_user_id, _mfa_type_code);
    end if;

    if not __is_enabled then
        perform error.raise_38002(_target_user_id, _mfa_type_code);
    end if;

    -- Invalidate previous valid MFA tokens for this user
    update auth.token
    set updated_at       = now(),
        updated_by       = _created_by,
        token_state_code = 'invalid'
    where user_id = _target_user_id
      and token_type_code = 'mfa'
      and token_state_code = 'valid';

    -- Create a new MFA challenge token (300s = 5 min default from token_type)
    select t.___token_uid, t.___expires_at
    from auth.create_token(
        _created_by, _user_id, _correlation_id,
        _target_user_id, null, null,
        'mfa', 'app',
        helpers.random_string(32),
        null,
        jsonb_build_object('mfa_type', _mfa_type_code, 'user_mfa_id', __user_mfa_id)
    ) t
    into __token_record;

    -- Log challenge creation event
    perform unsecure.create_user_event(
        _created_by, _user_id, _correlation_id, 'mfa_challenge_created',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('mfa_type', _mfa_type_code, 'token_uid', __token_record.___token_uid)
    );

    return query
        select __token_record.___token_uid, __token_record.___expires_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.verify_mfa_challenge
-- ---------------------------------------------------------------------------
-- Verifies an MFA challenge. The app verifies the TOTP code externally:
--   - _code_is_valid = true → challenge passed (TOTP code was correct)
--   - _code_is_valid = false + _recovery_code provided → try recovery code
--   - Neither valid → challenge failed, raises 38004
-- ---------------------------------------------------------------------------
create or replace function auth.verify_mfa_challenge(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _token_uid       text,
    _code_is_valid   boolean,
    _recovery_code   text default null,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
declare
    __token          auth.token;
    __recovery_hash  text;
    __recovery_codes text[];
    __idx            int;
    __user_mfa_id    bigint;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.verify_mfa_challenge');

    -- Fetch and validate the token
    select t.*
    from auth.token t
    where t.uid = _token_uid
      and t.token_type_code = 'mfa'
    into __token;

    if __token.token_id is null then
        perform error.raise_30005();
    end if;

    if __token.token_state_code <> 'valid' then
        perform error.raise_30002(_token_uid);
    end if;

    if __token.expires_at < now() then
        -- Mark as expired
        update auth.token
        set token_state_code = 'expired',
            updated_at       = now(),
            updated_by       = _updated_by
        where token_id = __token.token_id;

        perform error.raise_30002(_token_uid);
    end if;

    if __token.user_id <> _target_user_id then
        perform error.raise_30003(_token_uid);
    end if;

    -- Get user_mfa_id from token data
    __user_mfa_id := (__token.token_data ->> 'user_mfa_id')::bigint;

    -- Case 1: TOTP code is valid
    if _code_is_valid then
        -- Mark token as used
        update auth.token
        set token_state_code = 'used',
            used_at          = now(),
            updated_at       = now(),
            updated_by       = _updated_by
        where token_id = __token.token_id;

        -- Log success
        perform unsecure.create_user_event(
            _updated_by, _user_id, _correlation_id, 'mfa_challenge_passed',
            _target_user_id,
            _request_context := _request_context,
            _event_data := jsonb_build_object('mfa_type', __token.token_data ->> 'mfa_type',
                                              'token_uid', _token_uid, 'method', 'totp')
        );

        return;
    end if;

    -- Case 2: Try recovery code
    if _recovery_code is not null then
        __recovery_hash := encode(ext.digest(_recovery_code, 'sha256'), 'hex');

        select um.recovery_codes
        from auth.user_mfa um
        where um.user_mfa_id = __user_mfa_id
        into __recovery_codes;

        -- Find the recovery code in the array
        __idx := array_position(__recovery_codes, __recovery_hash);

        if __idx is not null then
            -- Remove the used recovery code
            __recovery_codes := array_remove(__recovery_codes, __recovery_hash);

            update auth.user_mfa
            set recovery_codes = __recovery_codes,
                updated_at     = now(),
                updated_by     = _updated_by
            where user_mfa_id = __user_mfa_id;

            -- Mark token as used
            update auth.token
            set token_state_code = 'used',
                used_at          = now(),
                updated_at       = now(),
                updated_by       = _updated_by
            where token_id = __token.token_id;

            -- Log recovery code usage
            perform unsecure.create_user_event(
                _updated_by, _user_id, _correlation_id, 'mfa_recovery_used',
                _target_user_id,
                _request_context := _request_context,
                _event_data := jsonb_build_object('mfa_type', __token.token_data ->> 'mfa_type',
                                                  'token_uid', _token_uid,
                                                  'recovery_codes_remaining', coalesce(array_length(__recovery_codes, 1), 0))
            );

            return;
        end if;
    end if;

    -- Case 3: Neither valid — mark token as failed
    update auth.token
    set token_state_code = 'failed',
        updated_at       = now(),
        updated_by       = _updated_by
    where token_id = __token.token_id;

    perform error.raise_38004();
end;
$$;
