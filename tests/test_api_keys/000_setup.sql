set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'API Keys Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test user with system_admin permissions
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
BEGIN
    RAISE NOTICE 'SETUP: Creating test user with system_admin...';

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('ak_test', 'ak_test', 'AK Test Admin', 'ak_test_admin', 'ak_test_admin@test.com', 'ak_test_admin@test.com', 'ak_test_admin@test.com', true)
    RETURNING user_id INTO __user_id;

    -- Assign system_admin perm set so the user has all API key permissions
    PERFORM unsecure.assign_permission_as_system(null::integer, __user_id, 'system_admin');

    -- Temp table to share IDs across test files (session-scoped in transaction mode)
    CREATE TEMP TABLE IF NOT EXISTS _ak_test_data (
        key text PRIMARY KEY,
        val text
    );
    DELETE FROM _ak_test_data;
    INSERT INTO _ak_test_data VALUES ('admin_id', __user_id::text);

    RAISE NOTICE 'SETUP: Created admin user_id=%', __user_id;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
