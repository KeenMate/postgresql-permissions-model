set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 6: auth.verify_user_by_email — correct hash returns user data
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __result         record;
    __event_exists   boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 6: verify_user_by_email — correct hash --';

    -- Call with the correct hash ('fakehash' from setup)
    SELECT * FROM auth.verify_user_by_email(
        __system_user_id, 'test-corr-06', 'autolock@test.com', 'fakehash'
    ) INTO __result;

    -- Verify user data returned
    IF __result.__user_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: verify_user_by_email returned NULL user_id';
    END IF;

    IF __result.__user_id != __test_user_id THEN
        RAISE EXCEPTION 'FAIL: verify_user_by_email returned wrong user_id: % (expected %)', __result.__user_id, __test_user_id;
    END IF;

    IF __result.__email != 'autolock@test.com' THEN
        RAISE EXCEPTION 'FAIL: verify_user_by_email returned wrong email: %', __result.__email;
    END IF;

    IF __result.__display_name != 'Test AutoLock User' THEN
        RAISE EXCEPTION 'FAIL: verify_user_by_email returned wrong display_name: %', __result.__display_name;
    END IF;

    RAISE NOTICE 'PASS: verify_user_by_email returned correct user data';

    -- Verify user_logged_in event was created
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_logged_in'
          AND ue.correlation_id = 'test-corr-06'
    ) INTO __event_exists;

    IF __event_exists THEN
        RAISE NOTICE 'PASS: user_logged_in event logged after successful verification';
    ELSE
        RAISE EXCEPTION 'FAIL: user_logged_in event not found';
    END IF;

    -- Verify no user_login_failed event was created for this correlation
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_login_failed'
          AND ue.correlation_id = 'test-corr-06'
    ) INTO __event_exists;

    IF NOT __event_exists THEN
        RAISE NOTICE 'PASS: No login failure event for successful verification';
    ELSE
        RAISE EXCEPTION 'FAIL: Unexpected user_login_failed event for successful verification';
    END IF;
END $$;
