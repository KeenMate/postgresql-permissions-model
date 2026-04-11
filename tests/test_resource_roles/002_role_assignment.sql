set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: assign_resource_role to a user
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 1: assign_resource_role assigns role to user';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT * FROM auth.assign_resource_role('test', __user_id_1, 'test-rra-1',
        'asset', '{"id": 100}'::jsonb,
        _target_user_id := __user_id_2,
        _role_codes := array['asset_reader'])
    INTO __result;

    IF __result.__role_code = 'asset_reader' AND __result.__resource_role_assignment_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Role assigned, assignment_id=%', __result.__resource_role_assignment_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected result: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: assign_resource_role to a group
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __group_id_1 integer;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 2: assign_resource_role assigns role to group';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val::integer FROM _rr_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    SELECT * FROM auth.assign_resource_role('test', __user_id_1, 'test-rra-2',
        'asset', '{"id": 200}'::jsonb,
        _user_group_id := __group_id_1,
        _role_codes := array['asset_editor'])
    INTO __result;

    IF __result.__role_code = 'asset_editor' THEN
        RAISE NOTICE '  PASS: Role assigned to group';
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected result: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: assign_resource_role is idempotent
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 3: assign_resource_role is idempotent';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Assign again — should not create duplicate
    PERFORM auth.assign_resource_role('test', __user_id_1, 'test-rra-3',
        'asset', '{"id": 100}'::jsonb,
        _target_user_id := __user_id_2,
        _role_codes := array['asset_reader']);

    SELECT count(*) FROM auth.resource_role_assignment
    WHERE resource_type = 'asset' AND resource_id = '{"id": 100}'::jsonb
      AND user_id = __user_id_2 AND role_code = 'asset_reader'
    INTO __count;

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: No duplicate — still 1 assignment';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: assign_resource_role rejects mismatched resource_type
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
BEGIN
    RAISE NOTICE 'TEST 4: assign_resource_role rejects type mismatch';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    BEGIN
        -- asset_reader is defined for 'asset', not 'asset.file'
        PERFORM auth.assign_resource_role('test', __user_id_1, 'test-rra-4',
            'asset.file', '{"id": 100, "file_id": 1}'::jsonb,
            _target_user_id := __user_id_2,
            _role_codes := array['asset_reader']);
        RAISE EXCEPTION '  FAIL: Expected exception but none was thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%defined for type%' THEN
            RAISE NOTICE '  PASS: Correct exception for type mismatch: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Wrong exception: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 5: assign multiple roles at once
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 5: assign multiple roles in one call';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    PERFORM auth.assign_resource_role('test', __user_id_1, 'test-rra-5',
        'asset', '{"id": 300}'::jsonb,
        _target_user_id := __user_id_3,
        _role_codes := array['asset_reader', 'asset_editor']);

    SELECT count(*) FROM auth.resource_role_assignment
    WHERE resource_type = 'asset' AND resource_id = '{"id": 300}'::jsonb
      AND user_id = __user_id_3
    INTO __count;

    IF __count = 2 THEN
        RAISE NOTICE '  PASS: 2 roles assigned in one call';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: revoke_resource_role removes specific role
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __deleted bigint;
    __remaining integer;
BEGIN
    RAISE NOTICE 'TEST 6: revoke_resource_role removes specific role';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    SELECT auth.revoke_resource_role('test', __user_id_1, 'test-rra-6',
        'asset', '{"id": 300}'::jsonb,
        _target_user_id := __user_id_3,
        _role_codes := array['asset_reader'])
    INTO __deleted;

    IF __deleted = 1 THEN
        RAISE NOTICE '  PASS: 1 role revoked';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 deleted, got %', __deleted;
    END IF;

    SELECT count(*) FROM auth.resource_role_assignment
    WHERE resource_type = 'asset' AND resource_id = '{"id": 300}'::jsonb
      AND user_id = __user_id_3
    INTO __remaining;

    IF __remaining = 1 THEN
        RAISE NOTICE '  PASS: 1 role remains (asset_editor)';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 remaining, got %', __remaining;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: revoke_resource_role with null role_codes revokes all
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __deleted bigint;
BEGIN
    RAISE NOTICE 'TEST 7: revoke_resource_role null role_codes revokes all';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    SELECT auth.revoke_resource_role('test', __user_id_1, 'test-rra-7',
        'asset', '{"id": 300}'::jsonb,
        _target_user_id := __user_id_3)
    INTO __deleted;

    IF __deleted = 1 THEN
        RAISE NOTICE '  PASS: Remaining role revoked';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 deleted, got %', __deleted;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: get_resource_role_assignments lists assignments
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 8: get_resource_role_assignments returns data';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    SELECT count(*) FROM auth.get_resource_role_assignments(
        __user_id_1, 'test-rra-8', 'asset', '{"id": 100}'::jsonb)
    INTO __count;

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: % assignment(s) found on asset 100', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 1, got %', __count;
    END IF;
END $$;
