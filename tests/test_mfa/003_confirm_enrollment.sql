set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 3: Confirm MFA enrollment (already confirmed in test 2b, verify state)
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __mfa_record   auth.user_mfa;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 3: Verify confirmed enrollment state --';

    SELECT * INTO __mfa_record
    FROM auth.user_mfa um
    WHERE um.user_id = __test_user_id AND um.mfa_type_code = 'totp';

    IF __mfa_record.is_confirmed AND __mfa_record.is_enabled THEN
        RAISE NOTICE 'PASS: MFA is confirmed and enabled';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected is_confirmed=true, is_enabled=true, got %, %', __mfa_record.is_confirmed, __mfa_record.is_enabled;
    END IF;

    IF __mfa_record.confirmed_at IS NOT NULL THEN
        RAISE NOTICE 'PASS: confirmed_at is set: %', __mfa_record.confirmed_at;
    ELSE
        RAISE EXCEPTION 'FAIL: confirmed_at should not be null';
    END IF;

    -- Verify confirmation event was logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'mfa_enrollment_confirmed'
    ) THEN
        RAISE NOTICE 'PASS: mfa_enrollment_confirmed event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_enrollment_confirmed event not found';
    END IF;
END $$;

-- Test 3b: Confirm with invalid code raises 38004
DO $$
DECLARE
    __test_user_id bigint;
    __result       record;
    __error_code   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 3b: Confirm with invalid code → 38004 --';

    -- Create a fresh user for this sub-test
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_mfa_confirm_fail', 'test_mfa_confirm_fail', 'mfa_confirm_fail@test.com', 'Test', 'normal', true, false, true)
    RETURNING user_id INTO __test_user_id;

    -- Enroll
    SELECT * INTO __result
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfa-03b', __test_user_id, 'totp', 'some_secret');

    -- Confirm with invalid code
    BEGIN
        PERFORM auth.confirm_mfa_enrollment('test', 1, 'test-corr-mfa-03b2', __test_user_id, 'totp', false);
        RAISE EXCEPTION 'FAIL: Should reject invalid confirmation code';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '38004' THEN
            RAISE NOTICE 'PASS: Invalid confirmation code rejected with error 38004';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 38004, got % (%)', __error_code, SQLERRM;
        END IF;
    END;
END $$;
