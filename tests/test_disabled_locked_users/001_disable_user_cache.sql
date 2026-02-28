set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 1: Cache exists before disable
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.disable_user_id')::bigint;
    __cache_exists boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 1: Cache exists before disable --';
    SELECT EXISTS(
        SELECT 1 FROM auth.user_permission_cache
        WHERE user_id = __test_user_id AND tenant_id = 1
    ) INTO __cache_exists;

    IF __cache_exists THEN
        RAISE NOTICE 'PASS: Permission cache exists before disable';
    ELSE
        RAISE EXCEPTION 'FAIL: Permission cache should exist before disable';
    END IF;
END $$;

-- ============================================================================
-- Test 2: disable_user clears permission cache
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.disable_user_id')::bigint;
    __cache_exists boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2: disable_user clears permission cache --';

    -- Disable the user
    PERFORM auth.disable_user('test', 1, null, __test_user_id);

    SELECT EXISTS(
        SELECT 1 FROM auth.user_permission_cache
        WHERE user_id = __test_user_id AND tenant_id = 1
    ) INTO __cache_exists;

    IF NOT __cache_exists THEN
        RAISE NOTICE 'PASS: Permission cache cleared when user disabled';
    ELSE
        RAISE EXCEPTION 'FAIL: Permission cache should be cleared when user disabled';
    END IF;
END $$;

-- ============================================================================
-- Test 3: Disabled user blocked from recalculate_user_permissions (error 33003)
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.disable_user_id')::bigint;
    __error_code text;
    __result record;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 3: Disabled user blocked from recalculate_user_permissions --';
    BEGIN
        SELECT * INTO __result FROM unsecure.recalculate_user_permissions('test', __test_user_id, 1);
        RAISE EXCEPTION 'FAIL: Disabled user should not be able to recalculate permissions';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
        IF SQLERRM LIKE '%not%active%' OR SQLERRM LIKE '%(33003)%' THEN
            RAISE NOTICE 'PASS: Disabled user blocked with appropriate error: %', SQLERRM;
        ELSE
            RAISE EXCEPTION 'FAIL: Expected "not active" error, got: % (%)', SQLERRM, __error_code;
        END IF;
    END;
END $$;
