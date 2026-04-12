set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 4: auth.create_perm_set creates a perm set
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __child_perm text := current_setting('test_pc.child_perm_code');
    __perm_set_id int;
    __perm_set_code text;
BEGIN
    RAISE NOTICE 'TEST 4: auth.create_perm_set - create perm set with permission';

    SELECT ps.perm_set_id, ps.code
    FROM auth.create_perm_set('perm_crud_test', __user_id, 'pc-corr-4', 'PC Test Perm Set',
        false, true, array[__child_perm]) ps
    INTO __perm_set_id, __perm_set_code;

    IF __perm_set_id IS NOT NULL AND __perm_set_code = 'pc_test_perm_set' THEN
        PERFORM set_config('test_pc.perm_set_id', __perm_set_id::text, false);
        PERFORM set_config('test_pc.perm_set_code', __perm_set_code, false);
        RAISE NOTICE '  PASS: perm set created (id=%, code=%)', __perm_set_id, __perm_set_code;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result (id=%, code=%)', __perm_set_id, __perm_set_code;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: auth.update_perm_set updates the title
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __perm_set_id int := current_setting('test_pc.perm_set_id')::int;
    __result_id int;
BEGIN
    RAISE NOTICE 'TEST 5: auth.update_perm_set - update perm set title';

    SELECT ps.perm_set_id
    FROM auth.update_perm_set('perm_crud_test', __user_id, 'pc-corr-5', __perm_set_id, 'PC Test Perm Set Updated') ps
    INTO __result_id;

    IF __result_id = __perm_set_id THEN
        RAISE NOTICE '  PASS: perm set updated (id=%)', __result_id;
    ELSE
        RAISE EXCEPTION '  FAIL: update returned unexpected id (expected=%, got=%)', __perm_set_id, __result_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: delete perm set by direct SQL (no auth.delete_perm_set function exists)
-- ============================================================================
DO $$
DECLARE
    __perm_set_id int := current_setting('test_pc.perm_set_id')::int;
    __still_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 6: delete perm set via direct SQL';

    -- Clean up assignment references first
    DELETE FROM auth.permission_assignment WHERE perm_set_id = __perm_set_id;
    DELETE FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;
    DELETE FROM auth.perm_set WHERE perm_set_id = __perm_set_id;

    SELECT exists(SELECT FROM auth.perm_set WHERE perm_set_id = __perm_set_id)
    INTO __still_exists;

    IF NOT __still_exists THEN
        RAISE NOTICE '  PASS: perm set deleted (id=%)', __perm_set_id;
    ELSE
        RAISE EXCEPTION '  FAIL: perm set still exists after delete (id=%)', __perm_set_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Recreate perm set for subsequent assignment tests
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __child_perm text := current_setting('test_pc.child_perm_code');
    __perm_set_id int;
    __perm_set_code text;
BEGIN
    RAISE NOTICE 'TEST 7: Recreate perm set for assignment tests';

    SELECT ps.perm_set_id, ps.code
    FROM auth.create_perm_set('perm_crud_test', __user_id, 'pc-corr-7', 'PC Test Perm Set 2',
        false, true, array[__child_perm]) ps
    INTO __perm_set_id, __perm_set_code;

    IF __perm_set_id IS NOT NULL THEN
        PERFORM set_config('test_pc.perm_set_id', __perm_set_id::text, false);
        PERFORM set_config('test_pc.perm_set_code', __perm_set_code, false);
        RAISE NOTICE '  PASS: perm set recreated (id=%, code=%)', __perm_set_id, __perm_set_code;
    ELSE
        RAISE EXCEPTION '  FAIL: could not recreate perm set';
    END IF;
END $$;
