set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 4: Get MFA status returns correct data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __result       record;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 4: Get MFA status --';

    SELECT * INTO __result
    FROM auth.get_mfa_status(1, 'test-corr-mfa-04', __test_user_id);

    IF __result.__user_mfa_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: get_mfa_status returned no rows';
    END IF;

    IF __result.__mfa_type_code = 'totp' THEN
        RAISE NOTICE 'PASS: mfa_type_code = totp';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected mfa_type_code=totp, got %', __result.__mfa_type_code;
    END IF;

    IF __result.__is_enabled AND __result.__is_confirmed THEN
        RAISE NOTICE 'PASS: is_enabled=true, is_confirmed=true';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected enabled+confirmed, got is_enabled=%, is_confirmed=%', __result.__is_enabled, __result.__is_confirmed;
    END IF;

    IF __result.__recovery_codes_remaining = 10 THEN
        RAISE NOTICE 'PASS: recovery_codes_remaining = 10';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 10 recovery codes remaining, got %', __result.__recovery_codes_remaining;
    END IF;

    RAISE NOTICE 'PASS: MFA status correct (enrolled_at=%, confirmed_at=%)', __result.__enrolled_at, __result.__confirmed_at;
END $$;
