set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Token CRUD Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Clean any leftover test data, create test users
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __target_id bigint;
BEGIN
    RAISE NOTICE 'SETUP: Cleaning leftover test data...';

    DELETE FROM auth.token WHERE created_by = 'tok_test';
    DELETE FROM public.journal WHERE created_by = 'tok_test';
    DELETE FROM auth.permission_assignment WHERE created_by = 'tok_test';
    DELETE FROM auth.user_permission_cache WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE 'tok_test_%');
    DELETE FROM auth.user_data WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE 'tok_test_%');
    DELETE FROM auth.user_info WHERE username LIKE 'tok_test_%';

    RAISE NOTICE 'SETUP: Creating test users...';

    -- Create admin user (will have token permissions via system_admin)
    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('tok_test', 'tok_test', 'Token Admin', 'tok_test_admin', 'tok_test_admin', 'tok_test_admin', 'tok_test_admin@test.com', true)
    RETURNING user_id INTO __admin_id;

    -- Give admin system_admin so they have all permissions
    PERFORM unsecure.assign_permission_as_system(null::integer, __admin_id, 'system_admin');

    -- Create target user (token will be created for this user)
    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('tok_test', 'tok_test', 'Token Target', 'tok_test_target', 'tok_test_target', 'tok_test_target', 'tok_test_target@test.com', true)
    RETURNING user_id INTO __target_id;

    -- Store IDs via temp table for cross-block access
    CREATE TEMP TABLE IF NOT EXISTS _tok_test_data (
        key text PRIMARY KEY,
        val bigint
    );
    DELETE FROM _tok_test_data;
    INSERT INTO _tok_test_data VALUES
        ('admin_id', __admin_id),
        ('target_id', __target_id);

    RAISE NOTICE 'SETUP: admin_id=%, target_id=%', __admin_id, __target_id;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
