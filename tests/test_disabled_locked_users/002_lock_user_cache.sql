set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 4: Cache exists before lock
-- ============================================================================
DO $$
DECLARE
    __test_user_id2 bigint := current_setting('test.lock_user_id')::bigint;
    __cache_exists boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 4: Cache exists before lock --';
    SELECT EXISTS(
        SELECT 1 FROM auth.user_permission_cache
        WHERE user_id = __test_user_id2 AND tenant_id = 1
    ) INTO __cache_exists;

    IF __cache_exists THEN
        RAISE NOTICE 'PASS: Permission cache exists before lock';
    ELSE
        RAISE EXCEPTION 'FAIL: Permission cache should exist before lock';
    END IF;
END $$;

-- ============================================================================
-- Test 5: lock_user clears permission cache
-- ============================================================================
DO $$
DECLARE
    __test_user_id2 bigint := current_setting('test.lock_user_id')::bigint;
    __cache_exists boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 5: lock_user clears permission cache --';

    -- Lock the user
    PERFORM auth.lock_user('test', 1, null, __test_user_id2);

    SELECT EXISTS(
        SELECT 1 FROM auth.user_permission_cache
        WHERE user_id = __test_user_id2 AND tenant_id = 1
    ) INTO __cache_exists;

    IF NOT __cache_exists THEN
        RAISE NOTICE 'PASS: Permission cache cleared when user locked';
    ELSE
        RAISE EXCEPTION 'FAIL: Permission cache should be cleared when user locked';
    END IF;
END $$;

-- ============================================================================
-- Test 6: Locked user blocked from recalculate_user_permissions (error 33004)
-- ============================================================================
DO $$
DECLARE
    __test_user_id2 bigint := current_setting('test.lock_user_id')::bigint;
    __error_code text;
    __result record;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 6: Locked user blocked from recalculate_user_permissions --';
    BEGIN
        SELECT * INTO __result FROM unsecure.recalculate_user_permissions('test', __test_user_id2, 1);
        RAISE EXCEPTION 'FAIL: Locked user should not be able to recalculate permissions';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        -- Note: error.raise_33004 may not exist yet, accept any error for locked user
        IF SQLERRM LIKE '%locked%' OR SQLERRM LIKE '%(33004)%' OR SQLERRM LIKE '%raise_33004%' THEN
            RAISE NOTICE 'PASS: Locked user blocked (error: %)', SQLERRM;
        ELSE
            RAISE EXCEPTION 'FAIL: Expected "locked" error, got: % (%)', SQLERRM, __error_code;
        END IF;
    END;
END $$;
