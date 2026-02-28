set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_group_id int;
    __test_permission_id int;
    __test_perm_set_id int;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test', 'test', 'normal', 'cache_test_user', 'cache_test_user', 'Cache Test User', 'cache_test@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Cache Test User'
    RETURNING user_id INTO __test_user_id;

    -- Create test group
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_assignable, is_active)
    VALUES ('test', 'test', 1, 'Cache Test Group', 'cache_test_group', true, true)
    ON CONFLICT DO NOTHING;

    SELECT user_group_id INTO __test_group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Add user to group
    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('test', __test_group_id, __test_user_id, 'manual')
    ON CONFLICT DO NOTHING;

    -- Create test permission
    INSERT INTO auth.permission (created_by, updated_by, title, code, full_code, node_path, is_assignable)
    VALUES ('test', 'test', 'Cache Test Permission', 'cache_test_perm', 'cache_test_perm'::ltree, '999'::ltree, true)
    ON CONFLICT DO NOTHING;

    SELECT permission_id INTO __test_permission_id FROM auth.permission WHERE code = 'cache_test_perm';

    -- Create test perm_set
    INSERT INTO auth.perm_set (created_by, updated_by, tenant_id, title, code, is_assignable)
    VALUES ('test', 'test', 1, 'Cache Test Perm Set', 'cache_test_perm_set', true)
    ON CONFLICT DO NOTHING;

    SELECT perm_set_id INTO __test_perm_set_id FROM auth.perm_set WHERE code = 'cache_test_perm_set' AND tenant_id = 1;

    RAISE NOTICE 'SETUP: Test user_id=%, group_id=%, permission_id=%, perm_set_id=%',
        __test_user_id, __test_group_id, __test_permission_id, __test_perm_set_id;
    RAISE NOTICE '';
END $$;
