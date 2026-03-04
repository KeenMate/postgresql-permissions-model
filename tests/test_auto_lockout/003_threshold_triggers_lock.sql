set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 3: Reaching threshold triggers auto-lock + event logged
-- ============================================================================
DO $$
DECLARE
    __test_user_id  bigint := current_setting('test.autolock_user_id')::bigint;
    __is_locked     boolean;
    __event_exists  boolean;
    __auto_locked   boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 3: Threshold triggers auto-lock --';

    -- We already have 1 failure from Test 2. Add 4 more to reach threshold of 5.
    FOR _i IN 2..5 LOOP
        PERFORM unsecure.create_user_event(
            'system', 1, 'test-corr-03', 'user_login_failed',
            __test_user_id,
            _event_data := jsonb_build_object('email', 'autolock@test.com', 'provider', 'email', 'reason', 'wrong_password')
        );
    END LOOP;

    -- Now check auto-lock (should return true — threshold reached)
    __auto_locked := unsecure.check_and_auto_lock_user('test', 'test-corr-03', __test_user_id);

    IF NOT __auto_locked THEN
        RAISE EXCEPTION 'FAIL: check_and_auto_lock_user should have returned true after 5 failures';
    END IF;

    RAISE NOTICE 'PASS: check_and_auto_lock_user returned true after threshold';

    -- Verify user is actually locked
    SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __test_user_id INTO __is_locked;

    IF __is_locked THEN
        RAISE NOTICE 'PASS: User is_locked = true after threshold';
    ELSE
        RAISE EXCEPTION 'FAIL: User should be locked after threshold';
    END IF;

    -- Verify user_auto_locked event was logged
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_auto_locked'
          AND ue.correlation_id = 'test-corr-03'
    ) INTO __event_exists;

    IF __event_exists THEN
        RAISE NOTICE 'PASS: user_auto_locked event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: user_auto_locked event not found';
    END IF;
END $$;
