set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 1: Enroll MFA — returns recovery codes, record is pending
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.mfa_user_id')::bigint;
    __result         record;
    __mfa_record     auth.user_mfa;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 1: Enroll MFA --';

    -- Enroll TOTP MFA
    SELECT * INTO __result
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfa-01', __test_user_id, 'totp', 'encrypted_secret_here');

    IF __result.__user_mfa_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: enroll_mfa should return a user_mfa_id';
    END IF;

    RAISE NOTICE 'PASS: enroll_mfa returned user_mfa_id = %', __result.__user_mfa_id;

    -- Verify recovery codes returned (10 codes)
    IF array_length(__result.__recovery_codes, 1) = 10 THEN
        RAISE NOTICE 'PASS: 10 recovery codes returned';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 10 recovery codes, got %', array_length(__result.__recovery_codes, 1);
    END IF;

    -- Store first recovery code for later use in recovery test
    PERFORM set_config('test.mfa_recovery_code', __result.__recovery_codes[1], false);

    -- Verify the record is pending (not confirmed, not enabled)
    SELECT * INTO __mfa_record
    FROM auth.user_mfa um
    WHERE um.user_mfa_id = __result.__user_mfa_id;

    IF NOT __mfa_record.is_confirmed AND NOT __mfa_record.is_enabled THEN
        RAISE NOTICE 'PASS: MFA enrollment is pending (is_confirmed=false, is_enabled=false)';
    ELSE
        RAISE EXCEPTION 'FAIL: MFA enrollment should be pending, got is_confirmed=%, is_enabled=%', __mfa_record.is_confirmed, __mfa_record.is_enabled;
    END IF;

    -- Verify recovery codes are stored as hashes (not plaintext)
    IF __mfa_record.recovery_codes[1] <> __result.__recovery_codes[1] THEN
        RAISE NOTICE 'PASS: Recovery codes stored as hashes (not plaintext)';
    ELSE
        RAISE EXCEPTION 'FAIL: Recovery codes appear to be stored as plaintext';
    END IF;

    -- Verify enrollment event was logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'mfa_enrolled'
    ) THEN
        RAISE NOTICE 'PASS: mfa_enrolled event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_enrolled event not found';
    END IF;
END $$;
