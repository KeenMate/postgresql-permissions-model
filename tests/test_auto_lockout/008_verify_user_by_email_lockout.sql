set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 8: auth.verify_user_by_email — locked user gets 33004
-- ============================================================================
-- Note: We cannot test repeated verify_user_by_email calls triggering lockout
-- via BEGIN..EXCEPTION blocks because PostgreSQL rolls back to savepoint on
-- exception, undoing both the failure events and the auto-lock.
-- Instead we manually insert failure events + lock the user, then verify
-- that verify_user_by_email raises 33004 for a locked user.
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8: verify_user_by_email — locked user raises 33004 --';

    -- Reset user state
    UPDATE auth.user_info SET is_locked = false WHERE user_id = __test_user_id;
    DELETE FROM auth.user_event
    WHERE target_user_id = __test_user_id
      AND event_type_code IN ('user_login_failed', 'user_auto_locked', 'user_logged_in');

    -- Insert 5 failure events to simulate threshold reached
    INSERT INTO auth.user_event (created_by, correlation_id, event_type_code, requester_user_id, target_user_id, event_data)
    SELECT 'test', 'test-corr-08-' || g, 'user_login_failed', 1, __test_user_id,
           jsonb_build_object('email', 'autolock@test.com', 'provider', 'email', 'reason', 'wrong_password')
    FROM generate_series(1, 5) g;

    -- Trigger auto-lockout via the direct function
    PERFORM unsecure.check_and_auto_lock_user('test', 'test-corr-08', __test_user_id);

    -- Verify user is now locked
    IF NOT (SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __test_user_id) THEN
        RAISE EXCEPTION 'FAIL: User should be locked after 5 failures + check_and_auto_lock_user';
    END IF;
    RAISE NOTICE 'PASS: User locked after 5 manual failure events + auto-lock check';

    -- Now verify that verify_user_by_email raises 33004 for the locked user
    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-08-locked', 'autolock@test.com', 'fakehash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for locked user';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33004' THEN
        RAISE NOTICE 'PASS: Locked user raised 33004 via verify_user_by_email';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33004 for locked user, got %', __error_code;
    END IF;
END $$;
