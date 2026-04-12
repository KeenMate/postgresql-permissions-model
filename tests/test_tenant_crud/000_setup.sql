set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Tenant CRUD Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create admin user with system_admin permissions
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __target_user_id bigint;
BEGIN
    RAISE NOTICE 'SETUP: Creating test admin user with system_admin...';

    -- Create admin user for performing tenant operations
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email, can_login)
    VALUES ('tenant_test', 'tenant_test', 'normal', 'tenant_test_admin', 'tenant_test_admin', 'Tenant Test Admin', 'tenant_test_admin@test.com', true)
    RETURNING user_id INTO __admin_id;

    -- Assign system_admin perm set so the user has all tenant permissions
    PERFORM unsecure.assign_permission_as_system(null::integer, __admin_id, 'system_admin');

    -- Create a secondary user for tenant membership / ownership tests
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email, can_login)
    VALUES ('tenant_test', 'tenant_test', 'normal', 'tenant_test_member', 'tenant_test_member', 'Tenant Test Member', 'tenant_test_member@test.com', true)
    RETURNING user_id INTO __target_user_id;

    -- Store IDs for subsequent tests (session-scoped in transaction mode)
    PERFORM set_config('test_tenant.admin_id', __admin_id::text, false);
    PERFORM set_config('test_tenant.target_user_id', __target_user_id::text, false);

    RAISE NOTICE 'SETUP: admin_id=%, target_user_id=%', __admin_id, __target_user_id;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
