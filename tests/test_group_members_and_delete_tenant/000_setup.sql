set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
DECLARE
    __test_user_id bigint;
    __test_group_id integer;
    __test_tenant_id integer;
    __test_tenant_uuid uuid;
BEGIN
    RAISE NOTICE '-- Setup --';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test_gm_dt', 'test_gm_dt', 'normal', 'test_gm_dt_user', 'test_gm_dt_user', 'Test GM DT User', 'test_gm_dt@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Test GM DT User'
    RETURNING user_id INTO __test_user_id;
    RAISE NOTICE 'Created test user: %', __test_user_id;

    -- Create test group
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_assignable, is_active)
    VALUES ('test_gm_dt', 'test_gm_dt', 1, 'Test GM DT Group', 'test_gm_dt_group', true, true)
    ON CONFLICT DO NOTHING;

    SELECT user_group_id INTO __test_group_id FROM auth.user_group WHERE code = 'test_gm_dt_group';
    RAISE NOTICE 'Created test group: %', __test_group_id;

    -- Add user to group
    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('test_gm_dt', __test_group_id, __test_user_id, 'manual')
    ON CONFLICT (user_group_id, user_id, coalesce(mapping_id, 0)) DO NOTHING;

    -- Create test tenant (for delete_tenant tests)
    INSERT INTO auth.tenant (created_by, updated_by, title, code, is_removable, is_assignable)
    VALUES ('test_gm_dt', 'test_gm_dt', 'Test GM DT Tenant', 'test_gm_dt_tenant', true, true)
    ON CONFLICT DO NOTHING;

    SELECT tenant_id, uuid INTO __test_tenant_id, __test_tenant_uuid
    FROM auth.tenant WHERE code = 'test_gm_dt_tenant';
    RAISE NOTICE 'Created test tenant: % (uuid: %)', __test_tenant_id, __test_tenant_uuid;

    -- Store IDs for subsequent tests
    PERFORM set_config('test_gm_dt.user_id', __test_user_id::text, false);
    PERFORM set_config('test_gm_dt.group_id', __test_group_id::text, false);
    PERFORM set_config('test_gm_dt.tenant_id', __test_tenant_id::text, false);
    PERFORM set_config('test_gm_dt.tenant_uuid', __test_tenant_uuid::text, false);
END;
$$;
