set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 13: get_users_groups_and_permissions — full permission resolution
-- ============================================================================
DO $$
DECLARE
    __user1_id bigint;
    __result_tenant_id int;
    __result_permissions text[];
    __has_perm_a boolean;
    __has_perm_b boolean;
BEGIN
    RAISE NOTICE 'TEST 13: get_users_groups_and_permissions — full resolution';

    __user1_id := current_setting('pchk.user1_id')::bigint;

    -- Clear cache to force fresh calculation
    PERFORM unsecure.clear_permission_cache('pchk_test', __user1_id, 1);

    -- Call get_users_groups_and_permissions (system user id=1 as admin)
    SELECT __tenant_id, __permissions
    INTO __result_tenant_id, __result_permissions
    FROM auth.get_users_groups_and_permissions('pchk_test', 1, 'pchk-corr-013', __user1_id, 1);

    -- Check that both test permissions are in the result
    __has_perm_a := 'pchk_test_perm_a' = ANY(__result_permissions);
    __has_perm_b := 'pchk_test_perm_b' = ANY(__result_permissions);

    IF __result_tenant_id IS NOT NULL AND __has_perm_a AND __has_perm_b THEN
        RAISE NOTICE '  PASS: Permissions resolved correctly — tenant=%, perms contain pchk_test_perm_a and pchk_test_perm_b', __result_tenant_id;
    ELSE
        RAISE EXCEPTION '  FAIL: tenant=%, has_perm_a=%, has_perm_b=%, permissions=%', __result_tenant_id, __has_perm_a, __has_perm_b, __result_permissions;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: get_users_groups_and_permissions — user without assignments
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __result_permissions text[];
    __has_perm_a boolean;
BEGIN
    RAISE NOTICE 'TEST 14: get_users_groups_and_permissions — user without direct assignments';

    __user2_id := current_setting('pchk.user2_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user2_id, 1);

    -- User2 was assigned to default group (in test 8), but has no direct permission assignments
    SELECT __permissions
    INTO __result_permissions
    FROM auth.get_users_groups_and_permissions('pchk_test', 1, 'pchk-corr-014', __user2_id, 1);

    -- User2 should NOT have pchk_test_perm_a (no perm_set assigned to them or their groups)
    __has_perm_a := 'pchk_test_perm_a' = ANY(coalesce(__result_permissions, ARRAY[]::text[]));

    IF NOT __has_perm_a THEN
        RAISE NOTICE '  PASS: User without assignments does not have test permission (permissions=%)', __result_permissions;
    ELSE
        RAISE EXCEPTION '  FAIL: User without assignments should not have pchk_test_perm_a, permissions=%', __result_permissions;
    END IF;
END $$;
