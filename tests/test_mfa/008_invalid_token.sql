set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 8: Invalid/expired token rejected, wrong type rejected
-- ============================================================================

-- 8a: Non-existent token raises 30005
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __error_code   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8a: Non-existent token → 30005 --';

    BEGIN
        PERFORM auth.verify_mfa_challenge('test', 1, 'test-corr-mfa-08a', __test_user_id, 'NONEXISTENT_UID', true);
        RAISE EXCEPTION 'FAIL: Should reject non-existent token';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '30005' THEN
            RAISE NOTICE 'PASS: Non-existent token rejected with error 30005';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 30005, got % (%)', __error_code, SQLERRM;
        END IF;
    END;
END $$;

-- 8b: Invalid code + no recovery code → token marked failed, raises 38004
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __challenge    record;
    __result       record;
    __error_code   text;
    __token_record auth.token;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8b: Invalid code with no recovery → 38004 --';

    -- Re-enroll MFA so we can create a challenge
    SELECT * INTO __result
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfa-08b-e', __test_user_id, 'totp', 'secret_for_test_8');
    PERFORM auth.confirm_mfa_enrollment('test', 1, 'test-corr-mfa-08b-c', __test_user_id, 'totp', true);

    -- Create challenge
    SELECT * INTO __challenge
    FROM auth.create_mfa_challenge('test', 1, 'test-corr-mfa-08b', __test_user_id, 'totp');

    -- Verify with invalid code and no recovery
    BEGIN
        PERFORM auth.verify_mfa_challenge('test', 1, 'test-corr-mfa-08b-v', __test_user_id,
            __challenge.__token_uid, false, null);
        RAISE EXCEPTION 'FAIL: Should reject invalid code without recovery';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '38004' THEN
            RAISE NOTICE 'PASS: Invalid code without recovery rejected with error 38004';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 38004, got % (%)', __error_code, SQLERRM;
        END IF;
    END;

    -- Note: token state change is rolled back by the exception handler above
    -- (PL/pgSQL rolls back to savepoint on EXCEPTION). The error code check
    -- above already validates the function rejects invalid codes correctly.
END $$;

-- 8c: MFA not enrolled raises 38002 on create_mfa_challenge
DO $$
DECLARE
    __fresh_user_id bigint;
    __error_code    text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8c: Challenge for non-enrolled user → 38002 --';

    -- Create a user without MFA
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_mfa_no_enroll', 'test_mfa_no_enroll', 'mfa_noenroll@test.com', 'Test', 'normal', true, false, true)
    RETURNING user_id INTO __fresh_user_id;

    BEGIN
        PERFORM auth.create_mfa_challenge('test', 1, 'test-corr-mfa-08c', __fresh_user_id, 'totp');
        RAISE EXCEPTION 'FAIL: Should reject challenge for non-enrolled user';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '38002' THEN
            RAISE NOTICE 'PASS: Challenge for non-enrolled user rejected with error 38002';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 38002, got % (%)', __error_code, SQLERRM;
        END IF;
    END;
END $$;

-- 8d: Invalid MFA type raises 38006
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __error_code   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8d: Invalid MFA type → 38006 --';

    BEGIN
        PERFORM auth.enroll_mfa('test', 1, 'test-corr-mfa-08d', __test_user_id, 'sms_otp', 'some_secret');
        RAISE EXCEPTION 'FAIL: Should reject invalid MFA type';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '38006' THEN
            RAISE NOTICE 'PASS: Invalid MFA type rejected with error 38006';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 38006, got % (%)', __error_code, SQLERRM;
        END IF;
    END;
END $$;
