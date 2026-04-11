set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: User with role assignment — has_resource_access returns true
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: User role assignment grants access';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 was assigned asset_reader on asset {"id": 100} in 002_role_assignment
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-1', 'asset', '{"id": 100}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: User has read access via asset_reader role';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: User with role — flag NOT in role returns false
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Flag not in role returns false';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- asset_reader only has 'read', not 'write'
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-2', 'asset', '{"id": 100}'::jsonb, 'write', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Write access denied — not in role';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Group role assignment — user inherits via group membership
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Group role assignment — user inherits access';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 is in group_id_1 (editors), which has asset_editor on asset {"id": 200}
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-3', 'asset', '{"id": 200}'::jsonb, 'write', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: User has write access via group role';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Group role — all flags in the role are accessible
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __read boolean;
    __write boolean;
    __delete boolean;
    __export boolean;
BEGIN
    RAISE NOTICE 'TEST 4: All flags in group role are accessible';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT auth.has_resource_access(__user_id_2, 'test-hra-4', 'asset', '{"id": 200}'::jsonb, 'read', 1, false) INTO __read;
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-4', 'asset', '{"id": 200}'::jsonb, 'write', 1, false) INTO __write;
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-4', 'asset', '{"id": 200}'::jsonb, 'delete', 1, false) INTO __delete;
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-4', 'asset', '{"id": 200}'::jsonb, 'export', 1, false) INTO __export;

    IF __read AND __write AND __delete AND __export THEN
        RAISE NOTICE '  PASS: All 4 flags (read/write/delete/export) accessible via asset_editor role';
    ELSE
        RAISE EXCEPTION '  FAIL: read=%, write=%, delete=%, export=%', __read, __write, __delete, __export;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: No role, no direct grant — access denied
-- ============================================================================
DO $$
DECLARE
    __user_id_3 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 5: No role, no grant — access denied';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    -- user_id_3 has no role or direct grant on asset {"id": 100}
    SELECT auth.has_resource_access(__user_id_3, 'test-hra-5', 'asset', '{"id": 100}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Access denied for unassigned user';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Direct flag grant + role — both work independently
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result_write boolean;
    __result_read boolean;
BEGIN
    RAISE NOTICE 'TEST 6: Direct flag + role coexist';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 has asset_reader (read) on asset 100
    -- Grant direct 'write' flag on same resource
    PERFORM auth.assign_resource_access('test', __user_id_1, 'test-hra-6', 'asset', '{"id": 100}'::jsonb,
        _target_user_id := __user_id_2, _access_flags := array['write']);

    SELECT auth.has_resource_access(__user_id_2, 'test-hra-6', 'asset', '{"id": 100}'::jsonb, 'read', 1, false) INTO __result_read;
    SELECT auth.has_resource_access(__user_id_2, 'test-hra-6', 'asset', '{"id": 100}'::jsonb, 'write', 1, false) INTO __result_write;

    IF __result_read AND __result_write THEN
        RAISE NOTICE '  PASS: Read from role, write from direct grant — both work';
    ELSE
        RAISE EXCEPTION '  FAIL: read=%, write=%', __result_read, __result_write;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: filter_accessible_resources includes role-derived access
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 7: filter_accessible_resources includes role-derived access';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT count(*) FROM auth.filter_accessible_resources(
        __user_id_2, 'test-hra-7', 'asset',
        array['{"id": 100}'::jsonb, '{"id": 200}'::jsonb, '{"id": 999}'::jsonb],
        'read')
    INTO __count;

    -- 100 via role, 200 via group role. 999 has no grant.
    IF __count = 2 THEN
        RAISE NOTICE '  PASS: 2 out of 3 resources accessible';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 accessible, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: get_resource_access_flags includes role-sourced flags
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __flags text[];
    __sources text[];
BEGIN
    RAISE NOTICE 'TEST 8: get_resource_access_flags includes role sources';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT array_agg(__access_flag order by __access_flag),
           array_agg(__source order by __access_flag)
    FROM auth.get_resource_access_flags(__user_id_2, 'test-hra-8', 'asset', '{"id": 100}'::jsonb)
    INTO __flags, __sources;

    -- Should have 'read' (from role) and 'write' (from direct grant)
    IF __flags @> array['read', 'write'] THEN
        RAISE NOTICE '  PASS: Flags=%, Sources=%', __flags, __sources;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected read+write, got flags=%, sources=%', __flags, __sources;
    END IF;
END $$;
