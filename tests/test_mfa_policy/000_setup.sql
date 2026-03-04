set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test users, group, enroll+confirm MFA for user1
-- ============================================================================
DO $$
DECLARE
    __user1_id   bigint;
    __user2_id   bigint;
    __group_id   integer;
    __enroll     record;
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test: MFA Policy';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '';
    RAISE NOTICE '-- Setup --';

    -- Create test user 1 (will have MFA enrolled+confirmed)
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_mfapol_user1', 'test_mfapol_user1', 'mfapol1@test.com', 'MFA Policy User 1', 'normal', true, false, true)
    RETURNING user_id INTO __user1_id;

    -- Create test user 2 (no MFA enrolled)
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_mfapol_user2', 'test_mfapol_user2', 'mfapol2@test.com', 'MFA Policy User 2', 'normal', true, false, true)
    RETURNING user_id INTO __user2_id;

    -- Create test group and add user1
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, group_type_code)
    VALUES ('test', 'test', 1, 'MFA Policy Test Group', 'mfapol_test_group', true, 'internal')
    RETURNING user_group_id INTO __group_id;

    INSERT INTO auth.user_group_member (created_by, updated_by, user_group_id, user_id)
    VALUES ('test', 'test', __group_id, __user1_id);

    -- Enroll + confirm MFA for user1 (needed for reset tests)
    SELECT * INTO __enroll
    FROM auth.enroll_mfa('test', 1, 'test-corr-mfapol-setup', __user1_id, 'totp', 'encrypted_secret_for_test');

    PERFORM auth.confirm_mfa_enrollment('test', 1, 'test-corr-mfapol-setup', __user1_id, 'totp', true);

    -- Store IDs for subsequent test files
    PERFORM set_config('test.mfapol_user1_id', __user1_id::text, false);
    PERFORM set_config('test.mfapol_user2_id', __user2_id::text, false);
    PERFORM set_config('test.mfapol_group_id', __group_id::text, false);

    RAISE NOTICE 'Created user1: % (id: %), user2: % (id: %), group: % (id: %)',
        'mfapol1@test.com', __user1_id, 'mfapol2@test.com', __user2_id, 'mfapol_test_group', __group_id;
END $$;
