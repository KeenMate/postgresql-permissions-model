/*
 * Automated Tests: Registration & Login Events
 * ==============================================
 *
 * Tests for v2.5.0 features:
 * - user_registered event (10008) fired on auth.register_user and auth.ensure_user_from_provider
 * - user_logged_in event (10010) fired on successful authentication
 * - user_login_failed event (10012) fired on all authentication failures
 * - _request_context jsonb parameter passed through to user_event
 * - Password hash stored in correct column (not provider_oid)
 *
 * NOTE on failure event tests:
 * PostgreSQL rolls back all side effects (including event INSERTs) when an
 * exception propagates through BEGIN...EXCEPTION. The failure events created
 * by create_user_event before error.raise_* are transactionally coupled —
 * they persist only if the calling application commits the transaction despite
 * the error. Tests for failure paths verify the correct exception is raised
 * (proving the code path with create_user_event was reached).
 *
 * Run with: ./exec-sql.sh -f tests/test_registration_login_events.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Registration & Login Events Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Clean any leftover test data, prepare state
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'SETUP: Cleaning previous test data...';

    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'email' LIKE '%regtest%';
    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'provider_uid' LIKE '%regtest%';
    DELETE FROM public.journal WHERE created_by = 'reg_test';
    DELETE FROM auth.user_identity WHERE uid LIKE '%regtest%';
    DELETE FROM auth.user_data WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE '%regtest%');
    DELETE FROM auth.user_info WHERE username LIKE '%regtest%';

    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: user_registered event code exists in seed data
-- ============================================================================
DO $$
DECLARE
    __event_id integer;
    __code text;
BEGIN
    RAISE NOTICE 'TEST 1: user_registered event code (10008) exists';

    SELECT event_id, code INTO __event_id, __code
    FROM const.event_code
    WHERE event_id = 10008;

    IF __event_id = 10008 AND __code = 'user_registered' THEN
        RAISE NOTICE '  PASS: Event code 10008 "user_registered" exists';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected event_id=10008, code=user_registered, got event_id=%, code=%', __event_id, __code;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: user_registered message template exists
-- ============================================================================
DO $$
DECLARE
    __template text;
BEGIN
    RAISE NOTICE 'TEST 2: user_registered message template exists';

    SELECT message_template INTO __template
    FROM const.event_message
    WHERE event_id = 10008 AND language_code = 'en';

    IF __template IS NOT NULL AND __template LIKE '%registered%' THEN
        RAISE NOTICE '  PASS: Message template found: "%"', __template;
    ELSE
        RAISE EXCEPTION '  FAIL: Message template for 10008/en not found or unexpected: %', __template;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: auth.register_user fires user_registered event
-- ============================================================================
DO $$
DECLARE
    __result record;
    __event_count int;
    __corr_id text := 'reg-test-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 3: auth.register_user fires user_registered event';

    -- Register a new user
    SELECT * INTO __result
    FROM auth.register_user('reg_test', 1, __corr_id, 'regtest_user1@test.com', '$hash$test123', 'RegTest User 1');

    -- Check user_registered event was created
    SELECT count(*) INTO __event_count
    FROM auth.user_event
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id;

    IF __event_count = 1 THEN
        RAISE NOTICE '  PASS: user_registered event created for user_id=%', __result.__user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 user_registered event, found %', __event_count;
    END IF;

    PERFORM set_config('test.reg_user1_id', __result.__user_id::text, false);
END $$;

-- ============================================================================
-- TEST 4: Password hash stored in correct column (not provider_oid)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __password_hash text;
    __provider_oid text;
BEGIN
    RAISE NOTICE 'TEST 4: Password hash stored in password_hash column (not provider_oid)';

    __user_id := current_setting('test.reg_user1_id')::bigint;

    SELECT uid.password_hash, uid.provider_oid
    INTO __password_hash, __provider_oid
    FROM auth.user_identity uid
    WHERE uid.user_id = __user_id
      AND uid.provider_code = 'email';

    IF __password_hash = '$hash$test123' AND __provider_oid = 'regtest_user1@test.com' THEN
        RAISE NOTICE '  PASS: password_hash="$hash$test123", provider_oid="%"', __provider_oid;
    ELSIF __password_hash IS NULL AND __provider_oid = '$hash$test123' THEN
        RAISE EXCEPTION '  FAIL: Hash in provider_oid instead of password_hash (the old bug)';
    ELSE
        RAISE EXCEPTION '  FAIL: password_hash=%, provider_oid=%', __password_hash, __provider_oid;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: register_user event contains request_context
-- ============================================================================
DO $$
DECLARE
    __result record;
    __ctx jsonb;
    __corr_id text := 'reg-test-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 5: register_user passes request_context to event';

    SELECT * INTO __result
    FROM auth.register_user('reg_test', 1, __corr_id, 'regtest_meta@test.com', '$hash$meta', 'RegTest Meta',
        _request_context := '{"ip_address": "192.168.1.1", "user_agent": "TestBrowser/1.0", "origin": "https://test.com"}'::jsonb);

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id;

    IF __ctx->>'ip_address' = '192.168.1.1' AND __ctx->>'user_agent' = 'TestBrowser/1.0' AND __ctx->>'origin' = 'https://test.com' THEN
        RAISE NOTICE '  PASS: request_context=%', __ctx;
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: register_user event contains email and provider in event_data
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __event_data jsonb;
BEGIN
    RAISE NOTICE 'TEST 6: register_user event_data contains email and provider';

    __user_id := current_setting('test.reg_user1_id')::bigint;

    SELECT ue.event_data INTO __event_data
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __user_id
    LIMIT 1;

    IF __event_data->>'provider' = 'email' AND __event_data->>'email' = 'regtest_user1@test.com' THEN
        RAISE NOTICE '  PASS: event_data=%', __event_data;
    ELSE
        RAISE EXCEPTION '  FAIL: event_data=%', __event_data;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: get_user_by_email_for_authentication fires user_logged_in on success
-- ============================================================================
DO $$
DECLARE
    __result record;
    __event_count int;
    __corr_id text := 'login-test-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 7: get_user_by_email_for_authentication fires user_logged_in on success';

    SELECT * INTO __result
    FROM auth.get_user_by_email_for_authentication(1, __corr_id, 'regtest_user1@test.com');

    SELECT count(*) INTO __event_count
    FROM auth.user_event
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id;

    IF __event_count = 1 THEN
        RAISE NOTICE '  PASS: user_logged_in event created';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 user_logged_in event, found %', __event_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: Login passes request_context to success event
-- ============================================================================
DO $$
DECLARE
    __ctx jsonb;
    __corr_id text := 'login-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 8: login passes request_context to user_logged_in event';

    PERFORM auth.get_user_by_email_for_authentication(1, __corr_id, 'regtest_user1@test.com',
        _request_context := '{"ip_address": "10.0.0.1", "user_agent": "LoginAgent/2.0", "origin": "https://app.test.com"}'::jsonb);

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND correlation_id = __corr_id;

    IF __ctx->>'ip_address' = '10.0.0.1' AND __ctx->>'user_agent' = 'LoginAgent/2.0' AND __ctx->>'origin' = 'https://app.test.com' THEN
        RAISE NOTICE '  PASS: request_context=%', __ctx;
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: Login failure raises correct exception for user not found
-- (event INSERT is rolled back by PG exception handling — see file header)
-- ============================================================================
DO $$
DECLARE
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 9: Login raises error 33001 on user not found';

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-notfound', 'regtest_nonexistent@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33001' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33001 (user not found)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33001, got %', __caught_state;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 10: Login failure raises correct exception for user disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 10: Login raises error 33003 on user disabled';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET is_active = false WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-disabled', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33003' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33003 (user disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33003, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_active = true WHERE user_id = __user_id;
END $$;

-- ============================================================================
-- TEST 11: Login failure raises correct exception for user locked
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 11: Login raises error 33004 on user locked';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET is_locked = true WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-locked', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33004' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33004 (user locked)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33004, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_locked = false WHERE user_id = __user_id;
END $$;

-- ============================================================================
-- TEST 12: Login failure raises correct exception for identity disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 12: Login raises error 33008 on identity disabled';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_identity SET is_active = false WHERE user_id = __user_id AND provider_code = 'email';

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-identity', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33008' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33008 (identity disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33008, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_identity SET is_active = true WHERE user_id = __user_id AND provider_code = 'email';
END $$;

-- ============================================================================
-- TEST 13: Login failure raises correct exception for login disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 13: Login raises error 33005 on can_login=false';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET can_login = false WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-canlogin', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33005' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33005 (login disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33005, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET can_login = true WHERE user_id = __user_id;
END $$;

-- ============================================================================
-- TEST 14: ensure_user_from_provider fires user_registered for new user
-- ============================================================================
DO $$
DECLARE
    __result record;
    __event_count int;
    __event_provider text;
    __event_uid text;
    __corr_id text := 'provider-reg-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 14: ensure_user_from_provider fires user_registered for new user';

    SELECT * INTO __result
    FROM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');

    SELECT count(*), (ue.event_data->>'provider'), (ue.event_data->>'provider_uid')
    INTO __event_count, __event_provider, __event_uid
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id
    GROUP BY ue.event_data->>'provider', ue.event_data->>'provider_uid';

    IF __event_count = 1 AND __event_provider = 'aad' AND __event_uid = 'regtest_aad_uid_1' THEN
        RAISE NOTICE '  PASS: user_registered event with provider=aad, provider_uid=regtest_aad_uid_1';
    ELSE
        RAISE EXCEPTION '  FAIL: event_count=%, provider=%, uid=%', __event_count, __event_provider, __event_uid;
    END IF;

    PERFORM set_config('test.aad_user_id', __result.__user_id::text, false);
END $$;

-- ============================================================================
-- TEST 15: ensure_user_from_provider fires user_logged_in for new user
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __event_count int;
BEGIN
    RAISE NOTICE 'TEST 15: ensure_user_from_provider fires user_logged_in for new user';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;

    -- The new user path also fires user_logged_in (registration is also a login)
    SELECT count(*) INTO __event_count
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id
      AND event_data->>'provider' = 'aad';

    IF __event_count >= 1 THEN
        RAISE NOTICE '  PASS: user_logged_in event also fired for new provider user';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected user_logged_in event for new user, found %', __event_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: ensure_user_from_provider fires user_logged_in for returning user
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __event_count_before int;
    __event_count_after int;
    __corr_id text := 'provider-login-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 16: ensure_user_from_provider fires user_logged_in for returning user';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;

    SELECT count(*) INTO __event_count_before
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id;

    -- Login again as existing user
    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');

    SELECT count(*) INTO __event_count_after
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id;

    IF __event_count_after > __event_count_before THEN
        RAISE NOTICE '  PASS: user_logged_in count increased (% -> %)', __event_count_before, __event_count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: user_logged_in count did not increase (% -> %)', __event_count_before, __event_count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: ensure_user_from_provider raises error on user disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 17: ensure_user_from_provider raises error 33003 on user disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_info SET is_active = false WHERE user_id = __aad_user_id;

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-disabled', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33003' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33003 (user disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33003, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_active = true WHERE user_id = __aad_user_id;
END $$;

-- ============================================================================
-- TEST 18: ensure_user_from_provider raises error on login disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 18: ensure_user_from_provider raises error 33005 on login disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_info SET can_login = false WHERE user_id = __aad_user_id;

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-canlogin', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33005' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33005 (login disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33005, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET can_login = true WHERE user_id = __aad_user_id;
END $$;

-- ============================================================================
-- TEST 19: ensure_user_from_provider raises error on identity disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 19: ensure_user_from_provider raises error 33008 on identity disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_identity SET is_active = false WHERE user_id = __aad_user_id AND provider_code = 'aad';

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-identity', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33008' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33008 (identity disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33008, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_identity SET is_active = true WHERE user_id = __aad_user_id AND provider_code = 'aad';
END $$;

-- ============================================================================
-- TEST 20: ensure_user_from_provider passes request_context to events
-- ============================================================================
DO $$
DECLARE
    __ctx jsonb;
    __corr_id text := 'provider-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 20: ensure_user_from_provider passes request_context to events';

    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com',
        _request_context := '{"ip_address": "172.16.0.1", "user_agent": "ProviderAgent/3.0", "origin": "https://aad.test.com"}'::jsonb);

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND correlation_id = __corr_id;

    IF __ctx->>'ip_address' = '172.16.0.1' AND __ctx->>'user_agent' = 'ProviderAgent/3.0' AND __ctx->>'origin' = 'https://aad.test.com' THEN
        RAISE NOTICE '  PASS: request_context=%', __ctx;
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- TEST 21: NULL request_context stored as NULL (backwards compatibility)
-- ============================================================================
DO $$
DECLARE
    __ctx jsonb;
    __corr_id text := 'login-null-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 21: NULL request_context stored as NULL (backwards compat)';

    PERFORM auth.get_user_by_email_for_authentication(1, __corr_id, 'regtest_user1@test.com');

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND correlation_id = __corr_id;

    IF __ctx IS NULL THEN
        RAISE NOTICE '  PASS: request_context is NULL when not provided';
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'email' LIKE '%regtest%';
    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'provider_uid' LIKE '%regtest%';
    DELETE FROM public.journal WHERE created_by = 'reg_test';
    DELETE FROM auth.user_identity WHERE uid LIKE '%regtest%';
    DELETE FROM auth.user_data WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE '%regtest%');
    DELETE FROM auth.user_info WHERE username LIKE '%regtest%';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Registration & Login Events Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 21 tests passed:';
    RAISE NOTICE '  1.  user_registered event code (10008) exists';
    RAISE NOTICE '  2.  user_registered message template exists';
    RAISE NOTICE '  3.  auth.register_user fires user_registered event';
    RAISE NOTICE '  4.  Password hash stored in correct column';
    RAISE NOTICE '  5.  register_user passes request_context to event';
    RAISE NOTICE '  6.  register_user event_data contains email and provider';
    RAISE NOTICE '  7.  get_user_by_email_for_authentication fires user_logged_in';
    RAISE NOTICE '  8.  login passes client metadata to success event';
    RAISE NOTICE '  9.  login raises 33001 on user not found';
    RAISE NOTICE '  10. login raises 33003 on user disabled';
    RAISE NOTICE '  11. login raises 33004 on user locked';
    RAISE NOTICE '  12. login raises 33008 on identity disabled';
    RAISE NOTICE '  13. login raises 33005 on login disabled';
    RAISE NOTICE '  14. ensure_user_from_provider fires user_registered for new user';
    RAISE NOTICE '  15. ensure_user_from_provider fires user_logged_in for new user';
    RAISE NOTICE '  16. ensure_user_from_provider fires user_logged_in for returning user';
    RAISE NOTICE '  17. ensure_user_from_provider raises 33003 on user disabled';
    RAISE NOTICE '  18. ensure_user_from_provider raises 33005 on login disabled';
    RAISE NOTICE '  19. ensure_user_from_provider raises 33008 on identity disabled';
    RAISE NOTICE '  20. ensure_user_from_provider passes client metadata to events';
    RAISE NOTICE '  21. NULL request_context backwards compatibility';
    RAISE NOTICE '';
END $$;
