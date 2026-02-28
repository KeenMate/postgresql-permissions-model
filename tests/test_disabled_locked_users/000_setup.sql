set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test users and populate permission cache
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_user_id2 bigint;
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test: Disabled and Locked Users Blocking';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '';
    RAISE NOTICE '-- Setup --';

    -- Create test user 1 (will be disabled)
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_disable_user', 'test_disable_user', 'test_disable@test.com', 'Test Disable User', 'normal', true, false, true)
    RETURNING user_id INTO __test_user_id;
    RAISE NOTICE 'Created test user 1 (to be disabled): %', __test_user_id;

    -- Create test user 2 (will be locked)
    INSERT INTO auth.user_info (created_by, updated_by, username, original_username, email, display_name, user_type_code, is_active, is_locked, can_login)
    VALUES ('test', 'test', 'test_lock_user', 'test_lock_user', 'test_lock@test.com', 'Test Lock User', 'normal', true, false, true)
    RETURNING user_id INTO __test_user_id2;
    RAISE NOTICE 'Created test user 2 (to be locked): %', __test_user_id2;

    -- Store user IDs in session config for subsequent test files
    PERFORM set_config('test.disable_user_id', __test_user_id::text, false);
    PERFORM set_config('test.lock_user_id', __test_user_id2::text, false);

    -- Pre-populate cache manually (simulating a cached session)
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __test_user_id, 1, t.uuid, ARRAY['test_group'], ARRAY['areas.public'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1;

    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __test_user_id2, 1, t.uuid, ARRAY['test_group'], ARRAY['areas.public'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1;

    RAISE NOTICE 'Pre-populated permission cache for both users';
END $$;
