set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test data for permission CRUD tests
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_target_id bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission CRUD Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Use system user (id=1) which has all permissions
    SELECT user_id INTO __test_user_id FROM auth.user_info WHERE user_id = 1;
    IF __test_user_id IS NULL THEN
        RAISE EXCEPTION 'SETUP FAILED: System user (id=1) not found';
    END IF;

    -- Create target user for permission assignment
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('perm_crud_test', 'perm_crud_test', 'normal', 'perm_crud_target', 'perm_crud_target', 'Perm CRUD Target', 'perm_crud_target@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Perm CRUD Target'
    RETURNING user_id INTO __test_target_id;

    -- Store IDs for subsequent tests
    PERFORM set_config('test_pc.user_id', __test_user_id::text, false);
    PERFORM set_config('test_pc.target_id', __test_target_id::text, false);

    RAISE NOTICE 'SETUP: user_id=%, target_id=%', __test_user_id, __test_target_id;
    RAISE NOTICE '';
END $$;
