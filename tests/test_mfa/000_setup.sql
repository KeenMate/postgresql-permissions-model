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
