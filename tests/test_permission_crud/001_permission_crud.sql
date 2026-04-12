set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: auth.create_permission creates a root permission
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __perm_id int;
    __db_code text;
    __db_full_code text;
BEGIN
    RAISE NOTICE 'TEST 1: auth.create_permission - create root permission';

    SELECT p.permission_id, p.code, p.full_code::text
    FROM auth.create_permission('perm_crud_test', __user_id, 'pc-corr-1', 'PC Test Root') p
    INTO __perm_id, __db_code, __db_full_code;

    IF __perm_id IS NOT NULL AND __db_code = 'pc_test_root' AND __db_full_code = 'pc_test_root' THEN
        PERFORM set_config('test_pc.root_perm_code', __db_full_code, false);
        RAISE NOTICE '  PASS: root permission created (id=%, code=%, full_code=%)', __perm_id, __db_code, __db_full_code;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result (id=%, code=%, full_code=%)', __perm_id, __db_code, __db_full_code;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: auth.create_permission creates a child permission under root
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __root_code text := current_setting('test_pc.root_perm_code');
    __perm_id int;
    __db_code text;
    __db_full_code text;
BEGIN
    RAISE NOTICE 'TEST 2: auth.create_permission - create child permission with parent';

    SELECT p.permission_id, p.code, p.full_code::text
    FROM auth.create_permission('perm_crud_test', __user_id, 'pc-corr-2', 'PC Test Child', __root_code) p
    INTO __perm_id, __db_code, __db_full_code;

    IF __perm_id IS NOT NULL AND __db_full_code = 'pc_test_root.pc_test_child' THEN
        PERFORM set_config('test_pc.child_perm_code', __db_full_code, false);
        RAISE NOTICE '  PASS: child permission created (id=%, code=%, full_code=%)', __perm_id, __db_code, __db_full_code;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result (id=%, code=%, full_code=%)', __perm_id, __db_code, __db_full_code;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Verify parent has_children flag after child creation
-- ============================================================================
DO $$
DECLARE
    __root_code text := current_setting('test_pc.root_perm_code');
    __has_children boolean;
BEGIN
    RAISE NOTICE 'TEST 3: parent permission has_children is true after child creation';

    SELECT exists(
        SELECT FROM auth.permission
        WHERE full_code <@ __root_code::ltree
          AND full_code <> __root_code::ltree
    ) INTO __has_children;

    IF __has_children THEN
        RAISE NOTICE '  PASS: parent has children';
    ELSE
        RAISE EXCEPTION '  FAIL: parent has no children';
    END IF;
END $$;
