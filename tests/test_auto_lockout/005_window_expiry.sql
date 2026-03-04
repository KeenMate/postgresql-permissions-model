set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 5: Old failures outside the window are not counted
-- ============================================================================
DO $$
DECLARE
    __new_user_id  bigint;
    __auto_locked  boolean;
    __is_locked    boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 5: Window expiry — old failures not counted --';

    -- Create a fresh unlocked user for this test
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_autolock_window', 'test_autolock_window', 'autolock_window@test.com', 'Test Window User', 'normal', true, false, true)
    RETURNING user_id INTO __new_user_id;

    -- Insert 5 failure events backdated to 20 minutes ago (outside 15-min window)
    INSERT INTO auth.user_event (created_at, created_by, correlation_id, event_type_code, requester_user_id, target_user_id, event_data)
    SELECT now() - interval '20 minutes',
           'test', 'test-corr-05', 'user_login_failed', 1, __new_user_id,
           jsonb_build_object('email', 'autolock_window@test.com', 'provider', 'email', 'reason', 'wrong_password')
    FROM generate_series(1, 5);

    -- Check auto-lock — should return false (all events are outside window)
    __auto_locked := unsecure.check_and_auto_lock_user('test', 'test-corr-05', __new_user_id);

    IF __auto_locked THEN
        RAISE EXCEPTION 'FAIL: Old failures outside window should not trigger lock';
    END IF;

    -- Verify user is still unlocked
    SELECT ui.is_locked FROM auth.user_info ui WHERE ui.user_id = __new_user_id INTO __is_locked;

    IF NOT __is_locked THEN
        RAISE NOTICE 'PASS: Old failures outside window not counted — user still unlocked';
    ELSE
        RAISE EXCEPTION 'FAIL: User should not be locked from expired failures';
    END IF;
END $$;
