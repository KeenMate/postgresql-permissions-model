set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
