set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 7: auth.assign_permission to group and get_effective_group_permissions
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_gc.user_id')::bigint;
    __group_id int := current_setting('test_gc.group_id')::int;
    __assignment_id bigint;
    __eff_count int;
BEGIN
    RAISE NOTICE 'TEST 7: auth.get_effective_group_permissions - assign perm then verify';

    -- Assign an individual permission to the group
    SELECT pa.assignment_id
    FROM auth.assign_permission('grp_crud_test', __user_id, 'gc-corr-7',
        __group_id, null, null, 'grp_crud_test_perm') pa
    INTO __assignment_id;

    IF __assignment_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: assign_permission to group returned NULL';
    END IF;

    PERFORM set_config('test_gc.group_assignment_id', __assignment_id::text, false);

    -- Get effective group permissions (bug regression test)
    SELECT count(*) INTO __eff_count
    FROM auth.get_effective_group_permissions('grp_crud_test', __user_id, 'gc-corr-7', __group_id);

    IF __eff_count >= 1 THEN
        RAISE NOTICE '  PASS: effective group permissions found (count=%, assignment_id=%)', __eff_count, __assignment_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected >= 1 effective permission, got %', __eff_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: auth.get_assigned_group_permissions returns assigned permissions
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_gc.user_id')::bigint;
    __group_id int := current_setting('test_gc.group_id')::int;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 8: auth.get_assigned_group_permissions - verify assigned perms';

    SELECT count(*) INTO __count
    FROM auth.get_assigned_group_permissions('grp_crud_test', __user_id, 'gc-corr-8', __group_id);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: assigned group permissions found (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected >= 1 assigned permission, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: Unassign permission from group and verify empty
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_gc.user_id')::bigint;
    __group_id int := current_setting('test_gc.group_id')::int;
    __assignment_id bigint := current_setting('test_gc.group_assignment_id')::bigint;
    __eff_count int;
BEGIN
    RAISE NOTICE 'TEST 9: Unassign permission from group and verify empty';

    PERFORM auth.unassign_permission('grp_crud_test', __user_id, 'gc-corr-9', __assignment_id);

    SELECT count(*) INTO __eff_count
    FROM auth.get_effective_group_permissions('grp_crud_test', __user_id, 'gc-corr-9', __group_id);

    IF __eff_count = 0 THEN
        RAISE NOTICE '  PASS: no effective permissions after unassignment';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 effective permissions, got %', __eff_count;
    END IF;
END $$;
