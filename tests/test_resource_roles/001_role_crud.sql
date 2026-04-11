set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_resource_role creates role with flags
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __result record;
    __flag_count integer;
BEGIN
    RAISE NOTICE 'TEST 1: create_resource_role creates role with flags';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    SELECT * FROM auth.create_resource_role('test', __user_id_1, 'test-rr-1',
        'test_role_1', 'asset', 'Test Role 1',
        _access_flags := array['read', 'write'],
        _source := 'test_crud')
    INTO __result;

    IF __result.__code = 'test_role_1' AND __result.__resource_type = 'asset'
       AND __result.__title = 'Test Role 1' AND __result.__is_active = true THEN
        RAISE NOTICE '  PASS: Role created with correct fields';
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected role data: %', __result;
    END IF;

    SELECT count(*) FROM const.resource_role_flag WHERE resource_role_code = 'test_role_1' INTO __flag_count;
    IF __flag_count = 2 THEN
        RAISE NOTICE '  PASS: Role has 2 flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flags, got %', __flag_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: create_resource_role is idempotent (on conflict do nothing)
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 2: create_resource_role is idempotent';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Call again with same code
    PERFORM auth.create_resource_role('test', __user_id_1, 'test-rr-2',
        'test_role_1', 'asset', 'Test Role 1 Duplicate',
        _access_flags := array['read', 'write', 'delete']);

    -- Should still be 1 role with this code
    SELECT count(*) FROM const.resource_role WHERE code = 'test_role_1' INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Idempotent — no duplicate created';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 role, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: update_resource_role updates mutable fields
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 3: update_resource_role updates mutable fields';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    SELECT * FROM auth.update_resource_role('test', __user_id_1, 'test-rr-3',
        'test_role_1', _title := 'Updated Title', _description := 'Updated desc')
    INTO __result;

    IF __result.__title = 'Updated Title' AND __result.__description = 'Updated desc' THEN
        RAISE NOTICE '  PASS: Title and description updated';
    ELSE
        RAISE EXCEPTION '  FAIL: Update failed: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: delete_resource_role removes role
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count bigint;
    __flag_count integer;
BEGIN
    RAISE NOTICE 'TEST 4: delete_resource_role removes role and flags';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    SELECT auth.delete_resource_role('test', __user_id_1, 'test-rr-4', 'test_role_1') INTO __count;

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: 1 role deleted';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 deleted, got %', __count;
    END IF;

    SELECT count(*) FROM const.resource_role_flag WHERE resource_role_code = 'test_role_1' INTO __flag_count;
    IF __flag_count = 0 THEN
        RAISE NOTICE '  PASS: Flags cascaded on delete';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 flags, got %', __flag_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: ensure_resource_roles bulk-creates roles
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 5: ensure_resource_roles bulk-creates roles';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    PERFORM auth.ensure_resource_roles('test', __user_id_1, 'test-rr-5', '[
        {"code": "bulk_role_a", "resource_type": "asset", "title": "Bulk A", "access_flags": ["read"]},
        {"code": "bulk_role_b", "resource_type": "asset", "title": "Bulk B", "access_flags": ["read", "write"]}
    ]'::jsonb, 'test_bulk');

    SELECT count(*) FROM const.resource_role WHERE source = 'test_bulk' INTO __count;
    IF __count = 2 THEN
        RAISE NOTICE '  PASS: 2 roles created via ensure';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 roles, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: ensure_resource_roles with is_final_state deactivates unlisted
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __is_active boolean;
BEGIN
    RAISE NOTICE 'TEST 6: ensure_resource_roles is_final_state deactivates unlisted';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Only include bulk_role_a — bulk_role_b should be deactivated
    PERFORM auth.ensure_resource_roles('test', __user_id_1, 'test-rr-6', '[
        {"code": "bulk_role_a", "resource_type": "asset", "title": "Bulk A", "access_flags": ["read"]}
    ]'::jsonb, 'test_bulk', true);

    SELECT r.is_active FROM const.resource_role r WHERE r.code = 'bulk_role_b' INTO __is_active;
    IF __is_active = false THEN
        RAISE NOTICE '  PASS: bulk_role_b deactivated by is_final_state';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected is_active=false, got %', __is_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: get_resource_roles returns roles with flags
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 7: get_resource_roles returns roles with aggregated flags';

    SELECT * FROM auth.get_resource_roles(_resource_type := 'asset')
    WHERE __code = 'asset_editor'
    INTO __result;

    IF __result.__access_flags @> array['read', 'write', 'delete', 'export'] THEN
        RAISE NOTICE '  PASS: asset_editor has expected flags: %', __result.__access_flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected read/write/delete/export, got %', __result.__access_flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: get_resource_role_flags returns individual flags
-- ============================================================================
DO $$
DECLARE
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 8: get_resource_role_flags lists flags in a role';

    SELECT count(*) FROM auth.get_resource_role_flags('asset_reader') INTO __count;
    IF __count = 1 THEN
        RAISE NOTICE '  PASS: asset_reader has 1 flag';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 flag, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: ensure_resource_role_flags updates flag set
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 9: ensure_resource_role_flags changes flag set';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Change asset_reader from [read] to [read, export]
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-rr-9',
        'asset_reader', array['read', 'export']);

    SELECT count(*) FROM const.resource_role_flag WHERE resource_role_code = 'asset_reader' INTO __count;
    IF __count = 2 THEN
        RAISE NOTICE '  PASS: asset_reader now has 2 flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flags, got %', __count;
    END IF;

    -- Revert back to [read] for remaining tests
    PERFORM auth.ensure_resource_role_flags('test', __user_id_1, 'test-rr-9b',
        'asset_reader', array['read']);
END $$;

-- ============================================================================
-- TEST 10: Invalid flag for resource type is rejected
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
BEGIN
    RAISE NOTICE 'TEST 10: Invalid flag for resource type is rejected';
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    BEGIN
        PERFORM auth.create_resource_role('test', __user_id_1, 'test-rr-10',
            'bad_role', 'asset', 'Bad Role',
            _access_flags := array['approve']);
        -- 'approve' is not in asset's per-type flags
        RAISE EXCEPTION '  FAIL: Expected exception but none was thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%not valid for resource type%' THEN
            RAISE NOTICE '  PASS: Correct exception for invalid flag: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Wrong exception: %', SQLERRM;
        END IF;
    END;
END $$;
