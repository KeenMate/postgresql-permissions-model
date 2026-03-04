set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 7: Disable MFA deletes the record
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.mfa_user_id')::bigint;
    __mfa_exists   boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 7: Disable MFA --';

    -- Disable MFA
    PERFORM auth.disable_mfa('test', 1, 'test-corr-mfa-07', __test_user_id, 'totp');

    -- Verify record is deleted
    SELECT EXISTS(
        SELECT 1 FROM auth.user_mfa um
        WHERE um.user_id = __test_user_id AND um.mfa_type_code = 'totp'
    ) INTO __mfa_exists;

    IF NOT __mfa_exists THEN
        RAISE NOTICE 'PASS: MFA record deleted after disable';
    ELSE
        RAISE EXCEPTION 'FAIL: MFA record should be deleted after disable';
    END IF;

    -- Verify mfa_disabled event was logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.target_user_id = __test_user_id
          AND ue.event_type_code = 'mfa_disabled'
    ) THEN
        RAISE NOTICE 'PASS: mfa_disabled event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_disabled event not found';
    END IF;

    -- Verify get_mfa_status returns empty
    IF NOT EXISTS(
        SELECT 1 FROM auth.get_mfa_status(1, 'test-corr-mfa-07s', __test_user_id)
    ) THEN
        RAISE NOTICE 'PASS: get_mfa_status returns empty after disable';
    ELSE
        RAISE EXCEPTION 'FAIL: get_mfa_status should return empty after disable';
    END IF;
END $$;
