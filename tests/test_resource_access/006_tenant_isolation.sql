set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Cross-tenant access is prevented
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __tenant_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Cross-tenant access is prevented';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val FROM _ra_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- Grant read to user_2 on document 3001 in tenant 1
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-iso-1a', 'document', 3001,
        _target_user_id := __user_id_2, _access_flags := array['read'], _tenant_id := 1);

    -- Verify access in tenant 1
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-iso-1b', 'document', 3001, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE EXCEPTION '  FAIL: Should have access in tenant 1';
    END IF;

    -- Verify NO access in tenant 2 (same resource_id, different tenant)
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-iso-1c', 'document', 3001, 'read', __tenant_id_2::integer, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Cross-tenant access correctly prevented';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false for cross-tenant, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Filter respects tenant boundaries
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __tenant_id_2 bigint;
    __result_t1 bigint[];
    __result_t2 bigint[];
BEGIN
    RAISE NOTICE 'TEST 2: Filter respects tenant boundaries';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val FROM _ra_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- Grant on different docs in different tenants
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-iso-2a', 'document', 3010,
        _target_user_id := __user_id_2, _access_flags := array['read'], _tenant_id := 1);

    -- Give user_id_1 the system admin perms in tenant 2
    PERFORM unsecure.assign_permission_as_system(null::integer, __user_id_1, 'system_admin', __tenant_id_2::integer);

    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-iso-2b', 'document', 3011,
        _target_user_id := __user_id_2, _access_flags := array['read'], _tenant_id := __tenant_id_2::integer);

    -- Filter in tenant 1
    SELECT array_agg(__resource_id)
    FROM auth.filter_accessible_resources(__user_id_2, 'test-corr-iso-2c', 'document',
        array[3010, 3011]::bigint[], 'read', 1)
    INTO __result_t1;

    -- Filter in tenant 2
    SELECT array_agg(__resource_id)
    FROM auth.filter_accessible_resources(__user_id_2, 'test-corr-iso-2d', 'document',
        array[3010, 3011]::bigint[], 'read', __tenant_id_2::integer)
    INTO __result_t2;

    IF __result_t1 = array[3010]::bigint[] AND __result_t2 = array[3011]::bigint[] THEN
        RAISE NOTICE '  PASS: Tenant 1 sees %, tenant 2 sees %', __result_t1, __result_t2;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected t1={3010}, t2={3011}, got t1=%, t2=%', __result_t1, __result_t2;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Grants in separate tenants are independent
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __tenant_id_2 bigint;
    __count_t1 integer;
    __count_t2 integer;
BEGIN
    RAISE NOTICE 'TEST 3: Grants in separate tenants are independent';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val FROM _ra_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- Count grants for user_2 in each tenant
    SELECT count(*) FROM auth.resource_access
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __count_t1;

    SELECT count(*) FROM auth.resource_access
    WHERE user_id = __user_id_2 AND tenant_id = __tenant_id_2::integer
    INTO __count_t2;

    IF __count_t1 > 0 AND __count_t2 > 0 AND __count_t1 <> __count_t2 THEN
        RAISE NOTICE '  PASS: Tenant grants are independent (t1=%, t2=%)', __count_t1, __count_t2;
    ELSIF __count_t1 > 0 AND __count_t2 > 0 THEN
        RAISE NOTICE '  PASS: Both tenants have grants (t1=%, t2=%)', __count_t1, __count_t2;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected grants in both tenants, got t1=%, t2=%', __count_t1, __count_t2;
    END IF;
END $$;
