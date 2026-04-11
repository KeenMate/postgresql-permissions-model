set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: User deny overrides role grant
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: User deny overrides role grant';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 has asset_reader (read) on asset 100 via role
    -- Deny 'read' explicitly
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-deny-1', 'asset', '{"id": 100}'::jsonb,
        __user_id_2, array['read']);

    SELECT auth.has_resource_access(__user_id_2, 'test-deny-1', 'asset', '{"id": 100}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Deny overrides role-derived read access';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false (deny should win), got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: User deny overrides group role grant
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: User deny overrides group role grant';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 is in editors group with asset_editor (write) on asset 200
    -- Deny 'write' for user_id_2 specifically
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-deny-2', 'asset', '{"id": 200}'::jsonb,
        __user_id_2, array['write']);

    SELECT auth.has_resource_access(__user_id_2, 'test-deny-2', 'asset', '{"id": 200}'::jsonb, 'write', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: User deny overrides group role write access';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Deny on one flag doesn't affect other flags from same role
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result_read boolean;
    __result_delete boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Deny on write does not affect read/delete from same role';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- asset_editor role has read/write/delete/export. Write was denied above.
    SELECT auth.has_resource_access(__user_id_2, 'test-deny-3', 'asset', '{"id": 200}'::jsonb, 'read', 1, false) INTO __result_read;
    SELECT auth.has_resource_access(__user_id_2, 'test-deny-3', 'asset', '{"id": 200}'::jsonb, 'delete', 1, false) INTO __result_delete;

    IF __result_read AND __result_delete THEN
        RAISE NOTICE '  PASS: Read and delete still work despite write deny';
    ELSE
        RAISE EXCEPTION '  FAIL: read=%, delete=%', __result_read, __result_delete;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: get_resource_access_flags excludes denied flags
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __flags text[];
BEGIN
    RAISE NOTICE 'TEST 4: get_resource_access_flags excludes denied flags';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT array_agg(__access_flag order by __access_flag)
    FROM auth.get_resource_access_flags(__user_id_2, 'test-deny-4', 'asset', '{"id": 200}'::jsonb)
    INTO __flags;

    IF 'write' != all(__flags) THEN
        RAISE NOTICE '  PASS: Write excluded from flags: %', __flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Write should not appear in %', __flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Revoking the deny restores role-derived access
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 5: Revoking deny restores role-derived access';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Revoke the deny on read for asset 100
    PERFORM auth.revoke_resource_access('test', __user_id_1, 'test-deny-5',
        'asset', '{"id": 100}'::jsonb,
        _target_user_id := __user_id_2,
        _access_flags := array['read']);

    SELECT auth.has_resource_access(__user_id_2, 'test-deny-5', 'asset', '{"id": 100}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: Role-derived read restored after deny revoked';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true after deny revoked, got %', __result;
    END IF;
END $$;
