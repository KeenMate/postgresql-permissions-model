set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Redefining a role's flags is instant — no cascade needed
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result_export_before boolean;
    __result_export_after boolean;
    __result_share_before boolean;
    __result_share_after boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Redefining role flags takes effect immediately';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 has asset_reader role on asset {"id": 100}
    -- asset_reader currently has [read] only

    -- Check: share is NOT accessible before redefinition
    SELECT auth.has_resource_access(__user_id_2, 'test-redef-1a', 'asset', '{"id": 100}'::jsonb, 'share', 1, false)
    INTO __result_share_before;

    -- Redefine asset_reader to [read, share]
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-redef-1b',
        'asset_reader', array['read', 'share']);

    -- Check: share IS accessible after redefinition — no cascade, no re-assignment
    SELECT auth.has_resource_access(__user_id_2, 'test-redef-1c', 'asset', '{"id": 100}'::jsonb, 'share', 1, false)
    INTO __result_share_after;

    IF __result_share_before = false AND __result_share_after = true THEN
        RAISE NOTICE '  PASS: share was false before, true after role redefinition';
    ELSE
        RAISE EXCEPTION '  FAIL: before=%, after=%', __result_share_before, __result_share_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Removing a flag from a role takes effect immediately
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result_share boolean;
    __result_read boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Removing flag from role takes effect immediately';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Revert asset_reader to [read] only (remove share)
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-redef-2a',
        'asset_reader', array['read']);

    SELECT auth.has_resource_access(__user_id_2, 'test-redef-2b', 'asset', '{"id": 100}'::jsonb, 'share', 1, false)
    INTO __result_share;

    SELECT auth.has_resource_access(__user_id_2, 'test-redef-2b', 'asset', '{"id": 100}'::jsonb, 'read', 1, false)
    INTO __result_read;

    IF __result_share = false AND __result_read = true THEN
        RAISE NOTICE '  PASS: Share removed, read preserved';
    ELSE
        RAISE EXCEPTION '  FAIL: share=%, read=%', __result_share, __result_read;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Redefinition doesn't affect direct flag grants
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __result_write boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Direct flag grant survives role redefinition';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- user_id_2 has direct 'write' on asset 100 (from test 003, test 6)
    SELECT auth.has_resource_access(__user_id_2, 'test-redef-3', 'asset', '{"id": 100}'::jsonb, 'write', 1, false)
    INTO __result_write;

    IF __result_write = true THEN
        RAISE NOTICE '  PASS: Direct write grant unaffected by role changes';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true (direct grant), got %', __result_write;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Redefinition of group role affects all members immediately
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result_share_before boolean;
    __result_share_after boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Group role redefinition affects all members instantly';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Revoke the deny on write that was set in deny tests
    PERFORM auth.revoke_resource_access('test', __user_id_1, 'test-redef-4-cleanup',
        'asset', '{"id": 200}'::jsonb,
        _target_user_id := __user_id_2,
        _access_flags := array['write']);

    -- Check: share not accessible via group role before
    SELECT auth.has_resource_access(__user_id_2, 'test-redef-4a', 'asset', '{"id": 200}'::jsonb, 'share', 1, false)
    INTO __result_share_before;

    -- Add 'share' to asset_editor role
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-redef-4b',
        'asset_editor', array['read', 'write', 'delete', 'export', 'share']);

    -- Check: share IS accessible now — no cascade needed
    SELECT auth.has_resource_access(__user_id_2, 'test-redef-4c', 'asset', '{"id": 200}'::jsonb, 'share', 1, false)
    INTO __result_share_after;

    IF __result_share_before = false AND __result_share_after = true THEN
        RAISE NOTICE '  PASS: Group role redefinition visible to all members immediately';
    ELSE
        RAISE EXCEPTION '  FAIL: before=%, after=%', __result_share_before, __result_share_after;
    END IF;

    -- Revert asset_editor to original flags
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-redef-4d',
        'asset_editor', array['read', 'write', 'delete', 'export']);
END $$;
