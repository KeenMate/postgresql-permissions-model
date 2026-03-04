set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 1: Reset MFA — returns 10 new codes, stored as hashes, event logged
-- ============================================================================
DO $$
DECLARE
    __user1_id       bigint := current_setting('test.mfapol_user1_id')::bigint;
    __result         record;
    __old_hashes     text[];
    __new_hashes     text[];
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 1: Reset MFA recovery codes --';

    -- Get current recovery code hashes before reset
    SELECT um.recovery_codes INTO __old_hashes
    FROM auth.user_mfa um
    WHERE um.user_id = __user1_id AND um.mfa_type_code = 'totp';

    -- Reset recovery codes
    SELECT * INTO __result
    FROM auth.reset_mfa('test', 1, 'test-corr-mfapol-01', __user1_id, 'totp');

    -- Should return user_mfa_id
    IF __result.__user_mfa_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: reset_mfa should return a user_mfa_id';
    END IF;
    RAISE NOTICE 'PASS: reset_mfa returned user_mfa_id = %', __result.__user_mfa_id;

    -- Should return exactly 10 codes
    IF array_length(__result.__recovery_codes, 1) = 10 THEN
        RAISE NOTICE 'PASS: 10 new recovery codes returned';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 10 recovery codes, got %', array_length(__result.__recovery_codes, 1);
    END IF;

    -- Verify new codes are stored as hashes (not plaintext)
    SELECT um.recovery_codes INTO __new_hashes
    FROM auth.user_mfa um
    WHERE um.user_id = __user1_id AND um.mfa_type_code = 'totp';

    IF __new_hashes[1] <> __result.__recovery_codes[1] THEN
        RAISE NOTICE 'PASS: New recovery codes stored as hashes (not plaintext)';
    ELSE
        RAISE EXCEPTION 'FAIL: Recovery codes appear to be stored as plaintext';
    END IF;

    -- Verify old codes were replaced (hashes differ)
    IF __old_hashes[1] <> __new_hashes[1] THEN
        RAISE NOTICE 'PASS: Old recovery codes replaced with new ones';
    ELSE
        RAISE EXCEPTION 'FAIL: Recovery codes were not replaced';
    END IF;

    -- Verify event logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __user1_id
          AND ue.event_type_code = 'mfa_recovery_reset'
    ) THEN
        RAISE NOTICE 'PASS: mfa_recovery_reset event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_recovery_reset event not found';
    END IF;
END $$;
