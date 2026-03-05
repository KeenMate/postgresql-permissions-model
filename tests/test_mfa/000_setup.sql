set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test user for MFA tests
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test: MFA';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '';
    RAISE NOTICE '-- Setup --';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_mfa_user', 'test_mfa_user', 'mfa@test.com', 'Test MFA User', 'normal', true, false, true)
    RETURNING user_id INTO __test_user_id;

    -- Store user ID for subsequent test files
    -- System user (id=1) has all permissions, used as caller
    PERFORM set_config('test.mfa_user_id', __test_user_id::text, false);

    RAISE NOTICE 'Created test user: % (id: %)', 'mfa@test.com', __test_user_id;
END $$;

-- ============================================================================
-- Verify all MFA permissions exist (created by 036_tables_mfa.sql)
-- ============================================================================
DO $$
DECLARE
    __missing text;
BEGIN
    SELECT string_agg(p, ', ')
    FROM unnest(ARRAY[
        'mfa', 'mfa.enroll_mfa', 'mfa.confirm_mfa_enrollment', 'mfa.disable_mfa',
        'mfa.get_mfa_status', 'mfa.create_mfa_challenge', 'mfa.verify_mfa_challenge'
    ]) AS p
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.permission perm WHERE perm.full_code::text = p
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing MFA permissions (from 036_tables_mfa.sql): %. Did setup run without errors?', __missing;
    END IF;
    RAISE NOTICE 'PASS: All required MFA permissions exist';
END $$;
