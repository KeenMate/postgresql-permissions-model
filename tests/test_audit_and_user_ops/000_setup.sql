set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test data for audit and user self-service tests
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __system_user_id bigint := 1;
    __tenant_uuid text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Audit Events & User Self-Service Ops Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';

    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email, is_active)
    VALUES ('audit_test', 'audit_test', 'normal', 'audit_test_user', 'audit_test_user', 'Audit Test User', 'audit_test@test.com', true)
    ON CONFLICT (username) DO UPDATE SET display_name = 'Audit Test User'
    RETURNING user_id INTO __test_user_id;

    -- Create email identity for the test user (needed for password update)
    INSERT INTO auth.user_identity (created_by, updated_by, user_id, provider_code, uid, provider_oid, password_hash, is_active)
    VALUES ('audit_test', 'audit_test', __test_user_id, 'email', 'audit_test@test.com', 'audit_test_oid', 'initial_hash', true)
    ON CONFLICT DO NOTHING;

    -- Assign test user to tenant 1 via user_group_member (so update_user_last_selected_tenant can find them)
    -- First ensure user is in a group that belongs to tenant 1
    INSERT INTO auth.user_group_member (created_by, user_id, user_group_id)
    SELECT 'audit_test', __test_user_id, ug.user_group_id
    FROM auth.user_group ug
    WHERE ug.tenant_id = 1
      AND ug.is_active = true
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- Get tenant 1 UUID for last_selected_tenant test
    SELECT t.uuid::text INTO __tenant_uuid
    FROM auth.tenant t
    WHERE t.tenant_id = 1;

    -- Store test values for subsequent tests
    PERFORM set_config('test.audit_user_id', __test_user_id::text, false);
    PERFORM set_config('test.audit_tenant_uuid', __tenant_uuid, false);

    RAISE NOTICE 'SETUP: Test user_id=%, tenant_uuid=%', __test_user_id, __tenant_uuid;
    RAISE NOTICE '';
END $$;
