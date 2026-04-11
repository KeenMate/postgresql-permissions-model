set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Role on parent type cascades to child via hierarchy walk-up
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: Parent role cascades to child type via hierarchy';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Assign asset_reader (resource_type='asset') to user_2 on asset {"id": 400}
    PERFORM auth.assign_resource_role('test', __user_id_1, 'test-hier-1',
        'asset', '{"id": 400}'::jsonb,
        _target_user_id := __user_id_2,
        _role_codes := array['asset_reader']);

    -- Check access on child type 'asset.file' with matching parent key
    -- has_resource_access walks up the hierarchy: asset.file → asset
    -- At 'asset' level, finds the role assignment with read flag
    SELECT auth.has_resource_access(__user_id_2, 'test-hier-1', 'asset.file',
        '{"id": 400, "file_id": 1}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: asset role on id=400 cascades to asset.file';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Deny on child type blocks parent role cascade
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Deny on child type blocks parent role cascade';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Deny 'read' on the specific asset.file
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-hier-2',
        'asset.file', '{"id": 400, "file_id": 1}'::jsonb,
        __user_id_2, array['read']);

    -- Check: should be denied even though parent role grants read
    SELECT auth.has_resource_access(__user_id_2, 'test-hier-2', 'asset.file',
        '{"id": 400, "file_id": 1}'::jsonb, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: Child deny blocks parent role cascade';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Deleting a role cascades to assignments
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 3: Deleting a role cascades to assignments (FK)';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Create a temporary role and assign it
    INSERT INTO const.resource_role (code, resource_type, source)
    VALUES ('temp_role', 'asset', 'test_roles');
    INSERT INTO const.resource_role_flag (resource_role_code, access_flag_code)
    VALUES ('temp_role', 'read');

    PERFORM auth.assign_resource_role('test', __user_id_1, 'test-hier-3',
        'asset', '{"id": 500}'::jsonb,
        _target_user_id := __user_id_1,
        _role_codes := array['temp_role']);

    -- Verify assignment exists
    SELECT count(*) FROM auth.resource_role_assignment WHERE role_code = 'temp_role' INTO __count;
    IF __count < 1 THEN
        RAISE EXCEPTION '  FAIL: Assignment should exist before delete';
    END IF;

    -- Delete the role
    DELETE FROM const.resource_role WHERE code = 'temp_role';

    -- Assignments should be cascade-deleted
    SELECT count(*) FROM auth.resource_role_assignment WHERE role_code = 'temp_role' INTO __count;
    IF __count = 0 THEN
        RAISE NOTICE '  PASS: Role deletion cascaded to assignments';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 assignments after role delete, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: get_resource_access_matrix includes role-derived flags
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __flags text[];
BEGIN
    RAISE NOTICE 'TEST 4: get_resource_access_matrix includes role-derived flags';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    SELECT array_agg(distinct __access_flag order by __access_flag)
    FROM auth.get_resource_access_matrix(__user_id_2, 'test-hier-4', 'asset', '{"id": 200}'::jsonb)
    WHERE __resource_type = 'asset'
    INTO __flags;

    -- user_id_2 has asset_editor via group on asset 200 = [read, write, delete, export]
    IF __flags @> array['read', 'write', 'delete', 'export'] THEN
        RAISE NOTICE '  PASS: Matrix includes role-derived flags: %', __flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected read/write/delete/export, got %', __flags;
    END IF;
END $$;
