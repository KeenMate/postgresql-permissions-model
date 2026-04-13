set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: has_permission — system user always passes
-- ============================================================================
DO $$
DECLARE
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: has_permission — system user (id=1) always passes';

    -- System user should pass any permission check
    SELECT auth.has_permission(1, 'pchk-corr-001', 'pchk_test_perm_a', 1, false) INTO __result;

    IF __result THEN
        RAISE NOTICE '  PASS: System user passed permission check';
    ELSE
        RAISE EXCEPTION '  FAIL: System user should always pass permission checks';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: has_permission — user with permission via perm_set
-- ============================================================================
DO $$
DECLARE
    __user1_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: has_permission — user with permission via perm_set';

    __user1_id := current_setting('pchk.user1_id')::bigint;

    -- Clear cache first to force recalculation
    PERFORM unsecure.clear_permission_cache('pchk_test', __user1_id, 1);

    SELECT auth.has_permission(__user1_id, 'pchk-corr-002', 'pchk_test_perm_a', 1, false) INTO __result;

    IF __result THEN
        RAISE NOTICE '  PASS: User with perm_set assignment passed permission check';
    ELSE
        RAISE EXCEPTION '  FAIL: User with perm_set assignment should pass permission check';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: has_permission — user without permission, _throw_err := false
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 3: has_permission — user without permission (_throw_err=false)';

    __user2_id := current_setting('pchk.user2_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user2_id, 1);

    SELECT auth.has_permission(__user2_id, 'pchk-corr-003', 'pchk_test_perm_a', 1, false) INTO __result;

    IF NOT __result THEN
        RAISE NOTICE '  PASS: User without permission returned false (no exception)';
    ELSE
        RAISE EXCEPTION '  FAIL: User without permission should return false';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: has_permission — user without permission, _throw_err := true
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 4: has_permission — user without permission (_throw_err=true, should throw)';

    __user2_id := current_setting('pchk.user2_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user2_id, 1);

    BEGIN
        SELECT auth.has_permission(__user2_id, 'pchk-corr-004', 'pchk_test_perm_a', 1, true) INTO __result;
        RAISE EXCEPTION '  FAIL: Expected exception was not thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%52109%' OR SQLERRM LIKE '%permission%' OR SQLSTATE = 'P0001' THEN
            RAISE NOTICE '  PASS: Permission denied exception thrown correctly';
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected exception: % (state: %)', SQLERRM, SQLSTATE;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 5: has_permissions — all permissions present
-- ============================================================================
DO $$
DECLARE
    __user1_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 5: has_permissions — all permissions present';

    __user1_id := current_setting('pchk.user1_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user1_id, 1);

    SELECT auth.has_permissions(__user1_id, 'pchk-corr-005', ARRAY['pchk_test_perm_a', 'pchk_test_perm_b'], 1, false) INTO __result;

    IF __result THEN
        RAISE NOTICE '  PASS: User with both permissions passed multi-check';
    ELSE
        RAISE EXCEPTION '  FAIL: User with both permissions should pass multi-check';
    END IF;
END $$;

-- ============================================================================
-- TEST 6: has_permissions — one permission missing, _throw_err := false
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 6: has_permissions — one permission missing (_throw_err=false)';

    __user2_id := current_setting('pchk.user2_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user2_id, 1);

    SELECT auth.has_permissions(__user2_id, 'pchk-corr-006', ARRAY['pchk_test_perm_a', 'pchk_test_perm_b'], 1, false) INTO __result;

    IF NOT __result THEN
        RAISE NOTICE '  PASS: User missing permissions returned false';
    ELSE
        RAISE EXCEPTION '  FAIL: User missing permissions should return false';
    END IF;
END $$;

-- ============================================================================
-- TEST 7: has_permissions — one permission missing, _throw_err := true
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 7: has_permissions — one permission missing (_throw_err=true, should throw)';

    __user2_id := current_setting('pchk.user2_id')::bigint;

    -- Clear cache
    PERFORM unsecure.clear_permission_cache('pchk_test', __user2_id, 1);

    BEGIN
        SELECT auth.has_permissions(__user2_id, 'pchk-corr-007', ARRAY['pchk_test_perm_a', 'pchk_test_perm_b'], 1, true) INTO __result;
        RAISE EXCEPTION '  FAIL: Expected exception was not thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%52109%' OR SQLERRM LIKE '%permission%' OR SQLSTATE = 'P0001' THEN
            RAISE NOTICE '  PASS: Permission denied exception thrown for multi-check';
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected exception: % (state: %)', SQLERRM, SQLSTATE;
        END IF;
    END;
END $$;
