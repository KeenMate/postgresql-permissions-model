set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
