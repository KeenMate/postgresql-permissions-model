set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 2: Re-enrollment of unconfirmed MFA replaces pending, confirmed blocks
-- ============================================================================

-- 2a: Re-enrolling while still unconfirmed should succeed (replaces pending)
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __result       record;
    __mfa_count    bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2a: Re-enroll unconfirmed replaces pending --';

    -- Re-enroll (should delete pending and create new)
    SELECT * INTO __result
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfa-02a', __test_user_id, 'totp', 'new_encrypted_secret');

    -- Verify only one enrollment exists
    SELECT count(*) FROM auth.user_mfa um
    WHERE um.user_id = __test_user_id AND um.mfa_type_code = 'totp'
    INTO __mfa_count;

    IF __mfa_count = 1 THEN
        RAISE NOTICE 'PASS: Re-enrollment replaced pending record (count = 1)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 1 MFA record after re-enrollment, got %', __mfa_count;
    END IF;

    -- Store recovery code from new enrollment
    PERFORM set_config('test.mfa_recovery_code', __result.__recovery_codes[1], false);
END $$;

-- 2b: Confirm, then try to re-enroll — should fail with 38001
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __error_code   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2b: Re-enroll after confirmed → 38001 --';

    -- Confirm the enrollment first
    PERFORM auth.confirm_mfa_enrollment('test', 1, 'test-corr-mfa-02b', __test_user_id, 'totp', true);

    -- Try to enroll again — should fail
    BEGIN
        PERFORM auth.enroll_mfa('test', 1, 'test-corr-mfa-02b2', __test_user_id, 'totp', 'another_secret');
        RAISE EXCEPTION 'FAIL: Should not be able to re-enroll confirmed MFA';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF __error_code = '38001' THEN
            RAISE NOTICE 'PASS: Re-enrollment of confirmed MFA blocked with error 38001';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected error 38001, got % (%)', __error_code, SQLERRM;
        END IF;
    END;
END $$;
