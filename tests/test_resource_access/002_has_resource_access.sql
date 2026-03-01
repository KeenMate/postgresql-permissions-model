set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Direct user grant — has_resource_access returns true
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Direct user grant - has_resource_access returns true';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read to user_2 on document 500
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-hra-1', 'document', 500,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    -- Check access
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-hra-1', 'document', 500, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: User has direct read access';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: No grant — has_resource_access returns false (no throw)
-- ============================================================================
DO $$
DECLARE
    __user_id_3 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: No grant - has_resource_access returns false';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    -- User_3 has no grant on document 500
    SELECT auth.has_resource_access(__user_id_3, 'test-corr-hra-2', 'document', 500, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: No access returns false';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: No grant — has_resource_access throws error (default)
-- ============================================================================
DO $$
DECLARE
    __user_id_3 bigint;
BEGIN
    RAISE NOTICE 'TEST 3: No grant - has_resource_access throws error';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    BEGIN
        PERFORM auth.has_resource_access(__user_id_3, 'test-corr-hra-3', 'document', 500, 'read', 1, true);
        RAISE EXCEPTION '  FAIL: Expected exception but none was thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%has no access to resource%' THEN
            RAISE NOTICE '  PASS: Correct exception thrown: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Wrong exception: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 4: Group grant — user inherits access via group membership
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Group grant - user inherits access via group membership';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read to editors group on document 600
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-hra-4', 'document', 600,
        _user_group_id := __group_id_1, _access_flags := array['read']);

    -- User_2 is a member of editors group
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-hra-4', 'document', 600, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: User inherits read access from group';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true (group grant), got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: System user (id=1) bypasses all checks
-- ============================================================================
DO $$
DECLARE
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 5: System user bypasses all resource access checks';

    -- No grants exist for system user on document 999, but system user should still pass
    SELECT auth.has_resource_access(1, 'test-corr-hra-5', 'document', 999, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: System user bypasses resource access checks';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true for system user, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Tenant owner bypasses all checks
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 6: Tenant owner bypasses all resource access checks';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Make user_1 a tenant owner
    INSERT INTO auth.owner (created_by, tenant_id, user_id)
    VALUES ('test', 1, __user_id_1);

    -- No direct grants exist for this resource, but owner should pass
    SELECT auth.has_resource_access(__user_id_1, 'test-corr-hra-6', 'document', 888, 'delete', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: Tenant owner bypasses resource access checks';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true for tenant owner, got %', __result;
    END IF;

    -- Clean up owner
    DELETE FROM auth.owner WHERE user_id = __user_id_1 AND tenant_id = 1;
END $$;

-- ============================================================================
-- TEST 7: Wrong flag returns false
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 7: Wrong flag returns false';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- User_2 has 'read' on document 500, but not 'write'
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-hra-7', 'document', 500, 'write', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Wrong flag correctly returns false';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false for wrong flag, got %', __result;
    END IF;
END $$;
