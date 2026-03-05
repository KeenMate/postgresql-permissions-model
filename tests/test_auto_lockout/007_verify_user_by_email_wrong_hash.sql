set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 7: auth.verify_user_by_email — wrong hash raises 52103
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
    __event_exists   boolean;
    __event_reason   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 7: verify_user_by_email — wrong hash --';

    -- Call with wrong hash
    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-07', 'autolock@test.com', 'wrong_hash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for wrong hash';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    -- Should raise 33001 (via error.raise_52103 → error.raise_33001)
    IF __error_code = '33001' THEN
        RAISE NOTICE 'PASS: Wrong hash raised error code 33001 (invalid credentials)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected error code 33001, got %', __error_code;
    END IF;

    -- Verify user_login_failed event logged with reason 'wrong_password'
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_login_failed'
          AND ue.correlation_id = 'test-corr-07'
    ) INTO __event_exists;

    IF NOT __event_exists THEN
        RAISE EXCEPTION 'FAIL: user_login_failed event not found for wrong hash';
    END IF;

    SELECT ue.event_data ->> 'reason'
    FROM auth.user_event ue
    WHERE ue.target_user_id = __test_user_id
      AND ue.event_type_code = 'user_login_failed'
      AND ue.correlation_id = 'test-corr-07'
    ORDER BY ue.created_at DESC
    LIMIT 1
    INTO __event_reason;

    IF __event_reason = 'wrong_password' THEN
        RAISE NOTICE 'PASS: user_login_failed event has reason=wrong_password';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected reason=wrong_password, got %', __event_reason;
    END IF;

    -- Verify NO user_logged_in event for this correlation
    SELECT EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'user_logged_in'
          AND ue.correlation_id = 'test-corr-07'
    ) INTO __event_exists;

    IF NOT __event_exists THEN
        RAISE NOTICE 'PASS: No user_logged_in event for failed verification';
    ELSE
        RAISE EXCEPTION 'FAIL: Unexpected user_logged_in event for wrong hash';
    END IF;
END $$;
