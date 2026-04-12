set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test data for group CRUD tests
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_target_id bigint;
    __test_perm_id int;
    __test_provider_id int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Group CRUD Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Use system user (id=1) which has all permissions
    SELECT user_id INTO __test_user_id FROM auth.user_info WHERE user_id = 1;
    IF __test_user_id IS NULL THEN
        RAISE EXCEPTION 'SETUP FAILED: System user (id=1) not found';
    END IF;

    -- Create target user for group membership
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('grp_crud_test', 'grp_crud_test', 'normal', 'grp_crud_target', 'grp_crud_target', 'Group CRUD Target', 'grp_crud_target@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Group CRUD Target'
    RETURNING user_id INTO __test_target_id;

    -- Create a test permission for assignment to groups
    INSERT INTO auth.permission (created_by, updated_by, code, full_code, node_path, is_assignable)
    VALUES ('grp_crud_test', 'grp_crud_test', 'grp_crud_test_perm', 'grp_crud_test_perm'::ltree, '998'::ltree, true)
    ON CONFLICT DO NOTHING;

    SELECT permission_id INTO __test_perm_id FROM auth.permission WHERE code = 'grp_crud_test_perm';

    -- Create a test provider for group mapping (with group mapping capability)
    INSERT INTO auth.provider (created_by, updated_by, code, is_active, allows_group_mapping)
    VALUES ('grp_crud_test', 'grp_crud_test', 'grp_crud_prov', true, true)
    ON CONFLICT DO NOTHING;

    SELECT provider_id INTO __test_provider_id FROM auth.provider WHERE code = 'grp_crud_prov';

    -- Store IDs for subsequent tests
    PERFORM set_config('test_gc.user_id', __test_user_id::text, false);
    PERFORM set_config('test_gc.target_id', __test_target_id::text, false);
    PERFORM set_config('test_gc.perm_id', __test_perm_id::text, false);
    PERFORM set_config('test_gc.provider_id', __test_provider_id::text, false);

    RAISE NOTICE 'SETUP: user_id=%, target_id=%, perm_id=%, provider_id=%',
        __test_user_id, __test_target_id, __test_perm_id, __test_provider_id;
    RAISE NOTICE '';
END $$;
