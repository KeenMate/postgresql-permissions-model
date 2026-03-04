set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 4: Already-locked user does not trigger duplicate auto-lock event
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __auto_locked    boolean;
    __event_count    bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 4: Already locked — no duplicate event --';

    -- Add another failure event
    PERFORM unsecure.create_user_event(
        'system', 1, 'test-corr-04', 'user_login_failed',
        __test_user_id,
        _event_data := jsonb_build_object('email', 'autolock@test.com', 'provider', 'email', 'reason', 'wrong_password')
    );

    -- Call auto-lock check again — should return false (already locked)
    __auto_locked := unsecure.check_and_auto_lock_user('test', 'test-corr-04', __test_user_id);

    IF __auto_locked THEN
        RAISE EXCEPTION 'FAIL: Should not re-lock an already locked user';
    END IF;

    -- Count auto_locked events — should still be exactly 1 from test 3
    SELECT count(*)
    FROM auth.user_event ue
    WHERE ue.target_user_id = __test_user_id
      AND ue.event_type_code = 'user_auto_locked'
    INTO __event_count;

    IF __event_count = 1 THEN
        RAISE NOTICE 'PASS: No duplicate user_auto_locked event (count = %)', __event_count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 1 user_auto_locked event, got %', __event_count;
    END IF;
END $$;
