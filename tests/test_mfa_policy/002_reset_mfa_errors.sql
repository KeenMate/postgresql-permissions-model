set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 2: Reset MFA errors — not enrolled (38002), not confirmed (38003)
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test.mfapol_user2_id')::bigint;
    __user1_id bigint := current_setting('test.mfapol_user1_id')::bigint;
    __result   record;
    __err_code text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2: Reset MFA error cases --';

    -- Case 1: Reset on non-enrolled user → 38002
    BEGIN
        SELECT * INTO __result
        FROM auth.reset_mfa('test', 1, 'test-corr-mfapol-02a', __user2_id, 'totp');
        RAISE EXCEPTION 'FAIL: reset_mfa should have raised 38002 for non-enrolled user';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '38002' THEN
            RAISE NOTICE 'PASS: reset_mfa raised 38002 for non-enrolled user';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected 38002, got %', __err_code;
        END IF;
    END;

    -- Case 2: Reset on unconfirmed enrollment → 38003
    -- Enroll MFA for user2 but do NOT confirm
    SELECT * INTO __result
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfapol-02b', __user2_id, 'totp', 'encrypted_secret_test');

    BEGIN
        SELECT * INTO __result
        FROM auth.reset_mfa('test', 1, 'test-corr-mfapol-02c', __user2_id, 'totp');
        RAISE EXCEPTION 'FAIL: reset_mfa should have raised 38003 for unconfirmed enrollment';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '38003' THEN
            RAISE NOTICE 'PASS: reset_mfa raised 38003 for unconfirmed enrollment';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected 38003, got %', __err_code;
        END IF;
    END;

    -- Clean up the unconfirmed enrollment
    DELETE FROM auth.user_mfa WHERE user_id = __user2_id;
END $$;
