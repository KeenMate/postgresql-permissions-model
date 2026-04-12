set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 14: unsecure.copy_perm_set with NULL _new_title (bug regression)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __perm_set_code text := current_setting('test_pc.perm_set_code');
    __copied_id int;
    __copied_code text;
BEGIN
    RAISE NOTICE 'TEST 14: unsecure.copy_perm_set - NULL _new_title (regression)';

    -- Copy to a different tenant with NULL title (should derive from source)
    -- Create a second tenant for the copy target
    INSERT INTO auth.tenant (created_by, updated_by, title, code)
    VALUES ('perm_crud_test', 'perm_crud_test', 'PC Copy Target Tenant', 'pc_copy_target')
    ON CONFLICT DO NOTHING;

    SELECT ps.perm_set_id, ps.code
    FROM unsecure.copy_perm_set('perm_crud_test', __user_id, 'pc-corr-14',
        __perm_set_code, 1,
        (SELECT tenant_id FROM auth.tenant WHERE code = 'pc_copy_target'),
        null) ps
    INTO __copied_id, __copied_code;

    IF __copied_id IS NOT NULL THEN
        PERFORM set_config('test_pc.copied_null_perm_set_id', __copied_id::text, false);
        RAISE NOTICE '  PASS: copy_perm_set with NULL title succeeded (id=%, code=%)', __copied_id, __copied_code;
    ELSE
        RAISE EXCEPTION '  FAIL: copy_perm_set with NULL title returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 15: unsecure.copy_perm_set with provided _new_title
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __perm_set_code text := current_setting('test_pc.perm_set_code');
    __copied_id int;
    __copied_code text;
BEGIN
    RAISE NOTICE 'TEST 15: unsecure.copy_perm_set - with provided _new_title';

    SELECT ps.perm_set_id, ps.code
    FROM unsecure.copy_perm_set('perm_crud_test', __user_id, 'pc-corr-15',
        __perm_set_code, 1, 1, 'PC Copied Perm Set Custom') ps
    INTO __copied_id, __copied_code;

    IF __copied_id IS NOT NULL AND __copied_code = 'pc_copied_perm_set_custom' THEN
        PERFORM set_config('test_pc.copied_custom_perm_set_id', __copied_id::text, false);
        RAISE NOTICE '  PASS: copy_perm_set with custom title (id=%, code=%)', __copied_id, __copied_code;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result (id=%, code=%)', __copied_id, __copied_code;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: Copied perm set inherits permissions from source
-- ============================================================================
DO $$
DECLARE
    __copied_id int := current_setting('test_pc.copied_custom_perm_set_id')::int;
    __perm_set_id int := current_setting('test_pc.perm_set_id')::int;
    __source_count int;
    __copy_count int;
BEGIN
    RAISE NOTICE 'TEST 16: Copied perm set inherits permissions from source';

    SELECT count(*) INTO __source_count
    FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;

    SELECT count(*) INTO __copy_count
    FROM auth.perm_set_perm WHERE perm_set_id = __copied_id;

    IF __copy_count = __source_count AND __copy_count > 0 THEN
        RAISE NOTICE '  PASS: copied perm set has % permissions (same as source)', __copy_count;
    ELSE
        RAISE EXCEPTION '  FAIL: permission count mismatch (source=%, copy=%)', __source_count, __copy_count;
    END IF;
END $$;
