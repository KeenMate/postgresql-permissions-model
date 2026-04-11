set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Role assignment in tenant 1 not visible in tenant 2
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __tenant_id_2 integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Role assignment scoped to tenant — invisible in other tenant';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _rr_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- user_id_2 has asset_reader on asset 100 in tenant 1
    -- Check in tenant 2 — should be false
    SELECT auth.has_resource_access(__user_id_2, 'test-iso-1', 'asset', '{"id": 100}'::jsonb, 'read', __tenant_id_2, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Role assignment in tenant 1 not visible in tenant 2';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false in tenant 2, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Same resource_id in different tenants — independent roles
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __tenant_id_2 integer;
    __result_t1 boolean;
    __result_t2 boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Same resource in different tenants has independent roles';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;
    SELECT val::integer FROM _rr_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- Assign role in tenant 2 (direct insert — user_id_1 lacks RBAC in tenant 2)
    INSERT INTO auth.resource_role_assignment (
        created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
        user_id, role_code, granted_by
    ) VALUES (
        'test', 'test', __tenant_id_2, 'asset', 'asset', '{"id": 100}'::jsonb,
        __user_id_3, 'asset_editor', __user_id_1
    );

    -- user_id_3 should have access in tenant 2
    SELECT auth.has_resource_access(__user_id_3, 'test-iso-2', 'asset', '{"id": 100}'::jsonb, 'write', __tenant_id_2, false)
    INTO __result_t2;

    -- user_id_3 should NOT have access in tenant 1 (no assignment there)
    SELECT auth.has_resource_access(__user_id_3, 'test-iso-2', 'asset', '{"id": 100}'::jsonb, 'write', 1, false)
    INTO __result_t1;

    IF __result_t2 = true AND __result_t1 = false THEN
        RAISE NOTICE '  PASS: Tenant isolation works — access in t2, denied in t1';
    ELSE
        RAISE EXCEPTION '  FAIL: t1=%, t2=%', __result_t1, __result_t2;
    END IF;
END $$;
