set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Invitation System Integration Test Suite - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test data
-- ============================================================================
DO $$
DECLARE
    __inviter_id bigint;
    __target_id bigint;
    __group_id integer;
    __tenant_id_2 integer;
BEGIN
    RAISE NOTICE 'SETUP: Creating test users, groups, tenants, action types...';

    -- Create inviter user (admin-like, will have permissions)
    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('test_inv', 'test_inv', 'Inv Inviter', 'inv_inviter', 'inv_inviter@test.com', 'inv_inviter@test.com', 'inv_inviter@test.com', true)
    RETURNING user_id INTO __inviter_id;

    -- Give inviter system_admin so they have all permissions
    PERFORM unsecure.assign_permission_as_system(null::integer, __inviter_id, 'system_admin');

    -- Create target user (the one being invited, simulates someone who already registered)
    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('test_inv', 'test_inv', 'Inv Target', 'inv_target', 'inv_target@test.com', 'inv_target@test.com', 'inv_target@test.com', true)
    RETURNING user_id INTO __target_id;

    -- Create a test group
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, is_assignable)
    VALUES ('test_inv', 'test_inv', 1, 'Inv Test Group ABC', 'inv_test_group_abc', true, true)
    RETURNING user_group_id INTO __group_id;

    -- Create second tenant for multi-tenant tests
    INSERT INTO auth.tenant (created_by, updated_by, title, code)
    VALUES ('test_inv', 'test_inv', 'Inv Test Tenant 2', 'inv_test_tenant_2')
    RETURNING tenant_id INTO __tenant_id_2;

    -- Register custom action type: send_sms_invite
    INSERT INTO const.invitation_action_type (code, title, executor_code, payload_schema, source)
    VALUES ('send_sms_invite', 'Send SMS Invitation', 'backend', '{
        "fields": {
            "mobile_phone":    {"type": "string",  "required": true,  "source": "invitation.target_email"},
            "invitation_uuid": {"type": "string",  "required": true,  "source": "invitation.uuid"},
            "message":         {"type": "string",  "required": false, "source": "invitation.message"},
            "tenant_id":       {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
        }
    }'::jsonb, 'test')
    ON CONFLICT DO NOTHING;

    -- Store test data IDs
    CREATE TEMP TABLE IF NOT EXISTS _inv_test_data (
        key text PRIMARY KEY,
        val bigint
    );
    DELETE FROM _inv_test_data;
    INSERT INTO _inv_test_data VALUES
        ('inviter_id', __inviter_id),
        ('target_id', __target_id),
        ('group_id', __group_id),
        ('tenant_id_2', __tenant_id_2);

    RAISE NOTICE 'SETUP: inviter=%, target=%, group=%, tenant_2=%',
        __inviter_id, __target_id, __group_id, __tenant_id_2;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
