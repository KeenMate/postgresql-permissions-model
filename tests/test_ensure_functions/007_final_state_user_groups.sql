set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 37: _is_final_state=true with null source raises error
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
BEGIN
    RAISE NOTICE 'TEST 37: ensure_user_groups - final_state with null source raises error';

    BEGIN
        PERFORM auth.ensure_user_groups(
            'test_ef', __user_id, __correlation_id,
            '[{"title": "Dummy Group"}]'::jsonb,
            1,      -- _tenant_id
            null,   -- _source = null
            true    -- _is_final_state = true
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown for null source with _is_final_state=true';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%_source is required%' THEN
                RAISE NOTICE '  PASS: Correctly raised error for null source (sqlerrm=%)', SQLERRM;
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 38: _is_final_state=false (default) does NOT remove groups
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
BEGIN
    RAISE NOTICE 'TEST 38: ensure_user_groups - default does NOT remove groups';

    -- Create 2 groups with source 'fs_grp_test'
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Group Alpha"},
            {"title": "FS Group Beta"}
        ]'::jsonb,
        1,
        'fs_grp_test'
    );

    SELECT count(*) INTO __count_before
    FROM auth.user_group WHERE source = 'fs_grp_test' AND tenant_id = 1;

    -- Call with only 1 group, _is_final_state defaults to false
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Group Alpha"}
        ]'::jsonb,
        1,
        'fs_grp_test'
    );

    SELECT count(*) INTO __count_after
    FROM auth.user_group WHERE source = 'fs_grp_test' AND tenant_id = 1;

    IF __count_before = __count_after AND __count_after = 2 THEN
        RAISE NOTICE '  PASS: Default mode did not remove groups (before=%, after=%)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Default mode should not remove (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 39: _is_final_state=true removes unlisted same-source groups
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count          int;
    __alpha_exists   boolean;
    __beta_exists    boolean;
BEGIN
    RAISE NOTICE 'TEST 39: ensure_user_groups - final_state removes unlisted same-source groups';

    -- Call with only Alpha, final_state=true => Beta should be removed
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Group Alpha"}
        ]'::jsonb,
        1,
        'fs_grp_test',
        true  -- _is_final_state
    );

    SELECT count(*) INTO __count FROM auth.user_group WHERE source = 'fs_grp_test' AND tenant_id = 1;

    SELECT
        exists(SELECT 1 FROM auth.user_group WHERE code = 'fs_group_alpha' AND tenant_id = 1),
        exists(SELECT 1 FROM auth.user_group WHERE code = 'fs_group_beta' AND tenant_id = 1)
    INTO __alpha_exists, __beta_exists;

    IF __count = 1 AND __alpha_exists AND NOT __beta_exists THEN
        RAISE NOTICE '  PASS: Final state removed Beta (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Final state removal wrong (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 40: _is_final_state=true does NOT remove different-source groups
-- ============================================================================
DO $$
DECLARE
    __user_id          bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id   text   := current_setting('test_ef.correlation_id');
    __count_other      int;
BEGIN
    RAISE NOTICE 'TEST 40: ensure_user_groups - final_state does NOT remove different source';

    -- Create a group with a different source
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "Other Source Group"}]'::jsonb,
        1,
        'other_grp_source'
    );

    -- Run final state for 'fs_grp_test' source
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Group Alpha"}
        ]'::jsonb,
        1,
        'fs_grp_test',
        true
    );

    SELECT count(*) INTO __count_other
    FROM auth.user_group WHERE source = 'other_grp_source' AND tenant_id = 1;

    IF __count_other = 1 THEN
        RAISE NOTICE '  PASS: Different source group untouched (count=%)', __count_other;
    ELSE
        RAISE EXCEPTION '  FAIL: Different source group affected (count=%)', __count_other;
    END IF;
END $$;

-- ============================================================================
-- TEST 41: _is_final_state=true cleans up mappings and permission_assignments
-- ============================================================================
DO $$
DECLARE
    __user_id          bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id   text   := current_setting('test_ef.correlation_id');
    __group_id         int;
    __mapping_count    int;
    __pa_count         int;
    __group_exists     boolean;
BEGIN
    RAISE NOTICE 'TEST 41: ensure_user_groups - final_state cleans up references before deleting';

    -- Create a doomed group
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Doomed Group", "is_external": true}]'::jsonb,
        1,
        'fs_grp_test'
    );

    SELECT user_group_id INTO __group_id
    FROM auth.user_group WHERE code = 'fs_doomed_group' AND tenant_id = 1;

    -- Create a mapping for the doomed group
    INSERT INTO auth.user_group_mapping (created_by, user_group_id, provider_code, mapped_object_id, mapped_object_name)
    VALUES ('test_ef', __group_id, 'test_ef_prov', 'doom-guid-001', 'Doom AAD Group');

    -- Create a permission assignment for the doomed group
    -- First ensure a permission exists
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Test Root", "is_assignable": false}, {"title": "FS Child A", "parent_code": "fs_test_root"}]'::jsonb,
        'fs_test'
    );

    INSERT INTO auth.permission_assignment (created_by, user_group_id, permission_id, tenant_id)
    SELECT 'test_ef', __group_id, p.permission_id, 1
    FROM auth.permission p WHERE p.full_code = 'fs_test_root.fs_child_a'::ltree;

    -- Now remove doomed group via final_state
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Group Alpha"}]'::jsonb,
        1,
        'fs_grp_test',
        true
    );

    SELECT count(*) INTO __mapping_count
    FROM auth.user_group_mapping WHERE user_group_id = __group_id;

    SELECT count(*) INTO __pa_count
    FROM auth.permission_assignment WHERE user_group_id = __group_id;

    SELECT exists(SELECT 1 FROM auth.user_group WHERE user_group_id = __group_id)
    INTO __group_exists;

    IF NOT __group_exists AND __mapping_count = 0 AND __pa_count = 0 THEN
        RAISE NOTICE '  PASS: References cleaned up (group=%, mappings=%, pa=%)', __group_exists, __mapping_count, __pa_count;
    ELSE
        RAISE EXCEPTION '  FAIL: References not cleaned (group=%, mappings=%, pa=%)', __group_exists, __mapping_count, __pa_count;
    END IF;
END $$;
