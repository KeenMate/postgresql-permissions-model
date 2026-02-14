/*
 * Automated Tests: Permission Short Codes
 * ========================================
 *
 * Tests for short_code feature:
 * - Auto-computed hierarchical short codes (e.g., 01.02.03)
 * - Custom short codes provided via _short_code parameter
 * - Short codes appear in views, return types, cache, and permissions map
 * - Unique constraint on short_code
 *
 * Run with: ./exec-sql.sh -f tests/test_short_code.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission Short Code Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: Existing seeded permissions have auto-computed short_code
-- ============================================================================
DO $$
DECLARE
    __total int;
    __with_code int;
BEGIN
    RAISE NOTICE 'TEST 1: Seeded permissions have auto-computed short_code';

    SELECT count(*), count(short_code)
    FROM auth.permission
    INTO __total, __with_code;

    IF __total > 0 AND __total = __with_code THEN
        RAISE NOTICE '  PASS: All % permissions have short_code populated', __total;
    ELSE
        RAISE EXCEPTION '  FAIL: % of % permissions have short_code', __with_code, __total;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Short codes follow hierarchical format (NN.NN...)
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 2: Short codes follow hierarchical format';

    -- All short_codes should match pattern: two-digit groups separated by dots
    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE short_code !~ '^[0-9]{2}(\.[0-9]{2})*$';

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All short_codes match NN.NN... format';
    ELSE
        RAISE EXCEPTION '  FAIL: % short_codes do not match expected format', __bad_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Root permissions have single-segment short_code (e.g., 01)
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 3: Root permissions have single-segment short_code';

    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE nlevel(node_path) = 1
      AND short_code LIKE '%.%';

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All root permissions have single-segment short_code';
    ELSE
        RAISE EXCEPTION '  FAIL: % root permissions have multi-segment short_code', __bad_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Child permissions have depth-matching short_code segments
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 4: Short code depth matches tree depth';

    -- Number of dot-separated segments should equal nlevel(node_path)
    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE array_length(string_to_array(short_code, '.'), 1) <> nlevel(node_path);

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All short_code depths match tree depths';
    ELSE
        RAISE EXCEPTION '  FAIL: % permissions have mismatched short_code depth', __bad_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: create_permission auto-computes short_code
-- ============================================================================
DO $$
DECLARE
    __perm auth.permission;
BEGIN
    RAISE NOTICE 'TEST 5: create_permission auto-computes short_code';

    SELECT * INTO __perm
    FROM unsecure.create_permission('test', 1, null, 'Short Code Test Root', null, true);

    IF __perm.short_code IS NOT NULL AND __perm.short_code ~ '^[0-9]{2}$' THEN
        RAISE NOTICE '  PASS: Auto-computed short_code = %', __perm.short_code;
    ELSE
        RAISE EXCEPTION '  FAIL: short_code is null or wrong format: %', __perm.short_code;
    END IF;

    -- Store for later tests
    PERFORM set_config('test.root_perm_id', __perm.permission_id::text, false);
    PERFORM set_config('test.root_short_code', __perm.short_code, false);
END $$;

-- ============================================================================
-- TEST 6: Child permission gets parent-prefixed short_code
-- ============================================================================
DO $$
DECLARE
    __perm auth.permission;
    __parent_short_code text;
BEGIN
    RAISE NOTICE 'TEST 6: Child permission gets parent-prefixed short_code';

    __parent_short_code := current_setting('test.root_short_code');

    SELECT * INTO __perm
    FROM unsecure.create_permission('test', 1, null, 'Short Code Test Child', 'short_code_test_root', true);

    IF __perm.short_code IS NOT NULL
       AND __perm.short_code LIKE __parent_short_code || '.%'
       AND __perm.short_code ~ '^[0-9]{2}\.[0-9]{2}$'
    THEN
        RAISE NOTICE '  PASS: Child short_code = % (parent = %)', __perm.short_code, __parent_short_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected %.XX, got %', __parent_short_code, __perm.short_code;
    END IF;

    PERFORM set_config('test.child_perm_id', __perm.permission_id::text, false);
END $$;

-- ============================================================================
-- TEST 7: Custom _short_code is used instead of auto-computed
-- ============================================================================
DO $$
DECLARE
    __perm auth.permission;
BEGIN
    RAISE NOTICE 'TEST 7: Custom _short_code is used instead of auto-computed';

    SELECT * INTO __perm
    FROM unsecure.create_permission('test', 1, null, 'Custom Code Perm', 'short_code_test_root', true, 'CUSTOM_01');

    IF __perm.short_code = 'CUSTOM_01' THEN
        RAISE NOTICE '  PASS: Custom short_code = %', __perm.short_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected CUSTOM_01, got %', __perm.short_code;
    END IF;

    PERFORM set_config('test.custom_perm_id', __perm.permission_id::text, false);
END $$;

-- ============================================================================
-- TEST 8: create_permission_as_system passes through _short_code
-- ============================================================================
DO $$
DECLARE
    __perm auth.permission;
BEGIN
    RAISE NOTICE 'TEST 8: create_permission_as_system passes through _short_code';

    SELECT * INTO __perm
    FROM unsecure.create_permission_as_system('System Custom Code', 'short_code_test_root', true, 'SYS_X7F9');

    IF __perm.short_code = 'SYS_X7F9' THEN
        RAISE NOTICE '  PASS: System custom short_code = %', __perm.short_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected SYS_X7F9, got %', __perm.short_code;
    END IF;

    PERFORM set_config('test.sys_custom_perm_id', __perm.permission_id::text, false);
END $$;

-- ============================================================================
-- TEST 9: create_permission_as_system without _short_code auto-computes
-- ============================================================================
DO $$
DECLARE
    __perm auth.permission;
BEGIN
    RAISE NOTICE 'TEST 9: create_permission_as_system without _short_code auto-computes';

    SELECT * INTO __perm
    FROM unsecure.create_permission_as_system('System Auto Code', 'short_code_test_root', true);

    IF __perm.short_code IS NOT NULL AND __perm.short_code ~ '^[0-9]{2}\.[0-9]{2}$' THEN
        RAISE NOTICE '  PASS: Auto-computed short_code = %', __perm.short_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected auto-computed NN.NN, got %', __perm.short_code;
    END IF;

    PERFORM set_config('test.sys_auto_perm_id', __perm.permission_id::text, false);
END $$;

-- ============================================================================
-- TEST 10: effective_permissions view uses permission_short_code
-- ============================================================================
DO $$
DECLARE
    __col_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 10: effective_permissions view has permission_short_code column';

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth'
          AND table_name = 'effective_permissions'
          AND column_name = 'permission_short_code'
    ) INTO __col_exists;

    IF __col_exists THEN
        RAISE NOTICE '  PASS: permission_short_code column exists in effective_permissions view';
    ELSE
        RAISE EXCEPTION '  FAIL: permission_short_code column not found in effective_permissions view';
    END IF;
END $$;

-- ============================================================================
-- TEST 11: get_permissions_map returns __short_code
-- ============================================================================
DO $$
DECLARE
    __row_count int;
    __null_count int;
BEGIN
    RAISE NOTICE 'TEST 11: get_permissions_map returns __short_code';

    SELECT count(*), count(*) - count(__short_code)
    FROM public.get_permissions_map()
    INTO __row_count, __null_count;

    IF __row_count > 0 AND __null_count = 0 THEN
        RAISE NOTICE '  PASS: get_permissions_map returns % rows, all with __short_code', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: % rows, % with null __short_code', __row_count, __null_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: get_all_permissions returns __short_code
-- ============================================================================
DO $$
DECLARE
    __row_count int;
    __null_count int;
BEGIN
    RAISE NOTICE 'TEST 12: get_all_permissions returns __short_code';

    SELECT count(*), count(*) - count(__short_code)
    FROM unsecure.get_all_permissions('test', 1)
    INTO __row_count, __null_count;

    IF __row_count > 0 AND __null_count = 0 THEN
        RAISE NOTICE '  PASS: get_all_permissions returns % rows, all with __short_code', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: % rows, % with null __short_code', __row_count, __null_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: Unique constraint on short_code prevents duplicates
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 13: Unique constraint prevents duplicate short_code';

    BEGIN
        -- Try to insert a permission with a duplicate custom short_code
        INSERT INTO auth.permission (created_by, updated_by, title, code, full_code, node_path, is_assignable, short_code)
        VALUES ('test', 'test', 'Dup Short Code', 'dup_sc', 'dup_sc'::ltree, '998'::ltree, true, 'CUSTOM_01');

        RAISE EXCEPTION '  FAIL: Expected unique violation was not thrown';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '  PASS: Unique constraint correctly prevents duplicate short_code';
    END;
END $$;

-- ============================================================================
-- TEST 14: short_code_permissions column exists in user_permission_cache
-- ============================================================================
DO $$
DECLARE
    __col_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 14: user_permission_cache has short_code_permissions column';

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth'
          AND table_name = 'user_permission_cache'
          AND column_name = 'short_code_permissions'
    ) INTO __col_exists;

    IF __col_exists THEN
        RAISE NOTICE '  PASS: short_code_permissions column exists in user_permission_cache';
    ELSE
        RAISE EXCEPTION '  FAIL: short_code_permissions column not found in user_permission_cache';
    END IF;
END $$;

-- ============================================================================
-- TEST 15: recalculate_user_permissions populates short_code_permissions
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __short_codes text[];
BEGIN
    RAISE NOTICE 'TEST 15: recalculate_user_permissions populates short_code_permissions';

    -- Create a test user with known permissions
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name)
    VALUES ('test_sc', 'test_sc', 'normal', 'sc_recalc_user', 'sc_recalc_user', 'SC Recalc User')
    RETURNING user_id INTO __test_user_id;

    -- Assign a perm_set that has permissions (system_admin has many)
    PERFORM unsecure.assign_permission('test_sc', 1, null, null, __test_user_id, 'system_admin', null, 1);

    -- Recalculate permissions
    SELECT __short_code_permissions INTO __short_codes
    FROM unsecure.recalculate_user_permissions('test_sc', __test_user_id, 1);

    IF __short_codes IS NOT NULL AND array_length(__short_codes, 1) > 0 THEN
        RAISE NOTICE '  PASS: short_code_permissions has % entries', array_length(__short_codes, 1);
    ELSE
        RAISE EXCEPTION '  FAIL: short_code_permissions is null or empty';
    END IF;

    -- Verify cache was populated with short_code_permissions
    IF EXISTS (
        SELECT 1 FROM auth.user_permission_cache
        WHERE user_id = __test_user_id AND tenant_id = 1
          AND array_length(short_code_permissions, 1) > 0
    ) THEN
        RAISE NOTICE '  PASS: Cache row has short_code_permissions populated';
    ELSE
        RAISE EXCEPTION '  FAIL: Cache row missing short_code_permissions';
    END IF;

    -- Cleanup
    DELETE FROM auth.permission_assignment WHERE user_id = __test_user_id;
    DELETE FROM auth.user_permission_cache WHERE user_id = __test_user_id;
    DELETE FROM auth.user_info WHERE user_id = __test_user_id;
END $$;

-- ============================================================================
-- TEST 16: compute_short_code returns null for nonexistent permission
-- ============================================================================
DO $$
DECLARE
    __result text;
BEGIN
    RAISE NOTICE 'TEST 16: compute_short_code returns null for nonexistent permission';

    SELECT unsecure.compute_short_code(999999) INTO __result;

    IF __result IS NULL THEN
        RAISE NOTICE '  PASS: Returns null for nonexistent permission_id';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected null, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
DECLARE
    __root_id int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    __root_id := current_setting('test.root_perm_id')::int;

    -- Clean up in reverse order of dependencies
    DELETE FROM auth.perm_set_perm WHERE permission_id IN (
        SELECT permission_id FROM auth.permission WHERE node_path <@ (
            SELECT node_path FROM auth.permission WHERE permission_id = __root_id
        )
    );
    DELETE FROM auth.permission_assignment WHERE permission_id IN (
        SELECT permission_id FROM auth.permission WHERE node_path <@ (
            SELECT node_path FROM auth.permission WHERE permission_id = __root_id
        )
    );
    -- Delete children first, then root (subtree)
    DELETE FROM auth.permission WHERE node_path <@ (
        SELECT node_path FROM auth.permission WHERE permission_id = __root_id
    );

    DELETE FROM journal WHERE created_by IN ('test', 'test_sc', 'system')
        AND data_payload::text LIKE '%short_code_test%';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission Short Code Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 16 tests passed:';
    RAISE NOTICE '  1.  Seeded permissions have auto-computed short_code';
    RAISE NOTICE '  2.  Short codes follow hierarchical NN.NN format';
    RAISE NOTICE '  3.  Root permissions have single-segment short_code';
    RAISE NOTICE '  4.  Short code depth matches tree depth';
    RAISE NOTICE '  5.  create_permission auto-computes short_code';
    RAISE NOTICE '  6.  Child permission gets parent-prefixed short_code';
    RAISE NOTICE '  7.  Custom _short_code overrides auto-computation';
    RAISE NOTICE '  8.  create_permission_as_system passes through _short_code';
    RAISE NOTICE '  9.  create_permission_as_system auto-computes when omitted';
    RAISE NOTICE '  10. effective_permissions view has permission_short_code';
    RAISE NOTICE '  11. get_permissions_map returns __short_code';
    RAISE NOTICE '  12. get_all_permissions returns __short_code';
    RAISE NOTICE '  13. Unique constraint prevents duplicate short_code';
    RAISE NOTICE '  14. user_permission_cache has short_code_permissions column';
    RAISE NOTICE '  15. recalculate_user_permissions populates short_code_permissions';
    RAISE NOTICE '  16. compute_short_code returns null for nonexistent permission';
    RAISE NOTICE '';
END $$;
