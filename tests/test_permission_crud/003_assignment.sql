set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 8: auth.assign_permission - assign perm set to user
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __target_id bigint := current_setting('test_pc.target_id')::bigint;
    __perm_set_code text := current_setting('test_pc.perm_set_code');
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 8: auth.assign_permission - assign perm set to user';

    SELECT pa.assignment_id
    FROM auth.assign_permission('perm_crud_test', __user_id, 'pc-corr-8',
        null, __target_id, __perm_set_code, null) pa
    INTO __assignment_id;

    IF __assignment_id IS NOT NULL THEN
        PERFORM set_config('test_pc.ps_assignment_id', __assignment_id::text, false);
        RAISE NOTICE '  PASS: perm set assigned (assignment_id=%)', __assignment_id;
    ELSE
        RAISE EXCEPTION '  FAIL: assign_permission returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 9: auth.assign_permission - assign individual permission to user
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __target_id bigint := current_setting('test_pc.target_id')::bigint;
    __root_perm text := current_setting('test_pc.root_perm_code');
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 9: auth.assign_permission - assign individual permission to user';

    SELECT pa.assignment_id
    FROM auth.assign_permission('perm_crud_test', __user_id, 'pc-corr-9',
        null, __target_id, null, __root_perm) pa
    INTO __assignment_id;

    IF __assignment_id IS NOT NULL THEN
        PERFORM set_config('test_pc.ind_assignment_id', __assignment_id::text, false);
        RAISE NOTICE '  PASS: individual permission assigned (assignment_id=%)', __assignment_id;
    ELSE
        RAISE EXCEPTION '  FAIL: assign_permission returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 10: auth.get_user_permissions shows both assignments
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __target_id bigint := current_setting('test_pc.target_id')::bigint;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 10: auth.get_user_permissions - verify assigned permissions';

    SELECT count(*) INTO __count
    FROM auth.get_user_permissions(__user_id, 'pc-corr-10', __target_id);

    IF __count >= 2 THEN
        RAISE NOTICE '  PASS: found % permissions for target user', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected >= 2 permissions, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: auth.unassign_permission - unassign perm set
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __ps_assignment_id bigint := current_setting('test_pc.ps_assignment_id')::bigint;
    __result_id bigint;
BEGIN
    RAISE NOTICE 'TEST 11: auth.unassign_permission - unassign perm set';

    SELECT pa.assignment_id
    FROM auth.unassign_permission('perm_crud_test', __user_id, 'pc-corr-11', __ps_assignment_id) pa
    INTO __result_id;

    IF __result_id = __ps_assignment_id THEN
        RAISE NOTICE '  PASS: perm set unassigned (assignment_id=%)', __result_id;
    ELSE
        RAISE EXCEPTION '  FAIL: unassign returned unexpected id (expected=%, got=%)', __ps_assignment_id, __result_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: auth.unassign_permission - unassign individual permission
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __ind_assignment_id bigint := current_setting('test_pc.ind_assignment_id')::bigint;
    __result_id bigint;
BEGIN
    RAISE NOTICE 'TEST 12: auth.unassign_permission - unassign individual permission';

    SELECT pa.assignment_id
    FROM auth.unassign_permission('perm_crud_test', __user_id, 'pc-corr-12', __ind_assignment_id) pa
    INTO __result_id;

    IF __result_id = __ind_assignment_id THEN
        RAISE NOTICE '  PASS: individual permission unassigned (assignment_id=%)', __result_id;
    ELSE
        RAISE EXCEPTION '  FAIL: unassign returned unexpected id (expected=%, got=%)', __ind_assignment_id, __result_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: auth.get_user_permissions returns nothing after unassignment
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_pc.user_id')::bigint;
    __target_id bigint := current_setting('test_pc.target_id')::bigint;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 13: auth.get_user_permissions - no permissions after unassignment';

    SELECT count(*) INTO __count
    FROM auth.get_user_permissions(__user_id, 'pc-corr-13', __target_id);

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: target user has 0 permissions after unassignment';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 permissions, got %', __count;
    END IF;
END $$;
