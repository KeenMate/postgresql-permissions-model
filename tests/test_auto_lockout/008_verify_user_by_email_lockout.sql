set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 8: auth.verify_user_by_email — repeated wrong hashes trigger auto-lockout
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
    __is_locked      boolean;
    __event_exists   boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8: verify_user_by_email — auto-lockout after repeated failures --';

    -- Ensure user starts unlocked (reset from previous tests)
    UPDATE auth.user_info SET is_locked = false WHERE user_id = __test_user_id;
    -- Clear any prior failure events to start fresh
    DELETE FROM auth.user_event
    WHERE target_user_id = __test_user_id
      AND event_type_code IN ('user_login_failed', 'user_auto_locked', 'user_logged_in');

    -- Send 4 wrong-hash attempts (should all raise 33001, no lockout yet)
    FOR _i IN 1..4 LOOP
        BEGIN
            PERFORM auth.verify_user_by_email(
                __system_user_id, 'test-corr-08-' || _i, 'autolock@test.com', 'bad_hash'
            );
        EXCEPTION WHEN OTHERS THEN
            -- Expected: 33001 (invalid credentials)
            NULL;
        END;
    END LOOP;

    -- Verify user is NOT yet locked
    SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __test_user_id INTO __is_locked;
    IF __is_locked THEN
        RAISE EXCEPTION 'FAIL: User should not be locked after only 4 failures';
    END IF;
    RAISE NOTICE 'PASS: User not locked after 4 failures';

    -- 5th attempt should trigger auto-lockout (raises 33004)
    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-08-5', 'autolock@test.com', 'bad_hash'
        );
        RAISE EXCEPTION 'FAIL: 5th attempt should have raised an error';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33004' THEN
        RAISE NOTICE 'PASS: 5th failure raised 33004 (user locked)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected error code 33004 on 5th failure, got %', __error_code;
    END IF;

    -- Verify user is now locked
    SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __test_user_id INTO __is_locked;
    IF __is_locked THEN
        RAISE NOTICE 'PASS: User is_locked = true after 5 failures';
    ELSE
        RAISE EXCEPTION 'FAIL: User should be locked after 5 failures';
    END IF;

    -- Verify user_auto_locked event was logged
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_auto_locked'
    ) INTO __event_exists;

    IF __event_exists THEN
        RAISE NOTICE 'PASS: user_auto_locked event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: user_auto_locked event not found';
    END IF;
END $$;
