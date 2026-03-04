set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 2: Single login failure does NOT lock the user
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.autolock_user_id')::bigint;
    __is_locked    boolean;
    __error_code   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2: Single failure does not lock --';

    -- Record a single login failure event directly
    PERFORM unsecure.create_user_event(
        'system', 1, 'test-corr-01', 'user_login_failed',
        __test_user_id,
        _event_data := jsonb_build_object('email', 'autolock@test.com', 'provider', 'email', 'reason', 'wrong_password')
    );

    -- Check auto-lock (should return false)
    IF unsecure.check_and_auto_lock_user('test', 'test-corr-01', __test_user_id) THEN
        RAISE EXCEPTION 'FAIL: User should NOT be locked after 1 failure';
    END IF;

    -- Verify user is still unlocked
    SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __test_user_id INTO __is_locked;

    IF NOT __is_locked THEN
        RAISE NOTICE 'PASS: User not locked after single failure';
    ELSE
        RAISE EXCEPTION 'FAIL: User should not be locked after single failure';
    END IF;
END $$;
