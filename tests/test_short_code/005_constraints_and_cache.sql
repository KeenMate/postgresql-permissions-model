set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
