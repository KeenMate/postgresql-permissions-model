set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 32: _is_final_state=true with null source raises error
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
BEGIN
    RAISE NOTICE 'TEST 32: ensure_perm_sets - final_state with null source raises error';

    BEGIN
        PERFORM auth.ensure_perm_sets(
            'test_ef', __user_id, __correlation_id,
            '[{"title": "Dummy Set", "permissions": []}]'::jsonb,
            null,   -- _source = null
            1,      -- _tenant_id
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
-- TEST 33: _is_final_state=false (default) does NOT remove perm sets
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
BEGIN
    RAISE NOTICE 'TEST 33: ensure_perm_sets - default does NOT remove sets';

    -- Ensure test permissions exist
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false},
            {"title": "FS Child A", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test'
    );

    -- Create 2 perm sets with source 'fs_ps_test'
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a"]},
            {"title": "FS Set Beta", "permissions": ["fs_test_root.fs_child_a"]}
        ]'::jsonb,
        'fs_ps_test'
    );

    SELECT count(*) INTO __count_before
    FROM auth.perm_set WHERE source = 'fs_ps_test' AND tenant_id = 1;

    -- Call with only 1 set, but _is_final_state defaults to false
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a"]}
        ]'::jsonb,
        'fs_ps_test'
    );

    SELECT count(*) INTO __count_after
    FROM auth.perm_set WHERE source = 'fs_ps_test' AND tenant_id = 1;

    IF __count_before = __count_after AND __count_after = 2 THEN
        RAISE NOTICE '  PASS: Default mode did not remove sets (before=%, after=%)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Default mode should not remove (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 34: _is_final_state=true removes unlisted same-source perm sets
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count          int;
    __alpha_exists   boolean;
    __beta_exists    boolean;
BEGIN
    RAISE NOTICE 'TEST 34: ensure_perm_sets - final_state removes unlisted same-source sets';

    -- Call with only Alpha, final_state=true => Beta should be removed
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a"]}
        ]'::jsonb,
        'fs_ps_test',
        1,
        true  -- _is_final_state
    );

    SELECT count(*) INTO __count FROM auth.perm_set WHERE source = 'fs_ps_test' AND tenant_id = 1;

    SELECT
        exists(SELECT 1 FROM auth.perm_set WHERE code = 'fs_set_alpha' AND tenant_id = 1),
        exists(SELECT 1 FROM auth.perm_set WHERE code = 'fs_set_beta' AND tenant_id = 1)
    INTO __alpha_exists, __beta_exists;

    IF __count = 1 AND __alpha_exists AND NOT __beta_exists THEN
        RAISE NOTICE '  PASS: Final state removed Beta (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Final state removal wrong (count=%, alpha=%, beta=%)', __count, __alpha_exists, __beta_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 35: _is_final_state=true does NOT remove different-source perm sets
-- ============================================================================
DO $$
DECLARE
    __user_id          bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id   text   := current_setting('test_ef.correlation_id');
    __count_other      int;
BEGIN
    RAISE NOTICE 'TEST 35: ensure_perm_sets - final_state does NOT remove different source';

    -- Create a perm set with a different source
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "Other Source Set", "permissions": ["fs_test_root.fs_child_a"]}]'::jsonb,
        'other_ps_source'
    );

    -- Run final state for 'fs_ps_test' source
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a"]}
        ]'::jsonb,
        'fs_ps_test',
        1,
        true
    );

    SELECT count(*) INTO __count_other
    FROM auth.perm_set WHERE source = 'other_ps_source' AND tenant_id = 1;

    IF __count_other = 1 THEN
        RAISE NOTICE '  PASS: Different source perm set untouched (count=%)', __count_other;
    ELSE
        RAISE EXCEPTION '  FAIL: Different source perm set affected (count=%)', __count_other;
    END IF;
END $$;

-- ============================================================================
-- TEST 36: _is_final_state=true syncs permissions within existing set (removes extras)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __perm_set_id    int;
    __perm_count     int;
    __has_a          boolean;
BEGIN
    RAISE NOTICE 'TEST 36: ensure_perm_sets - final_state syncs permissions within set';

    -- Ensure we have extra permissions
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Child B", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test'
    );

    -- Add extra permission to Alpha set (non-final-state, so it just adds)
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a", "fs_test_root.fs_child_b"]}
        ]'::jsonb,
        'fs_ps_test'
    );

    SELECT ps.perm_set_id INTO __perm_set_id
    FROM auth.perm_set ps WHERE ps.code = 'fs_set_alpha' AND ps.tenant_id = 1;

    -- Verify it has 2 permissions now
    SELECT count(*) INTO __perm_count FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;
    IF __perm_count != 2 THEN
        RAISE EXCEPTION '  FAIL: Setup - expected 2 permissions in set, got %', __perm_count;
    END IF;

    -- Now call final_state with only child_a => child_b should be removed from set
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Set Alpha", "permissions": ["fs_test_root.fs_child_a"]}
        ]'::jsonb,
        'fs_ps_test',
        1,
        true
    );

    SELECT count(*) INTO __perm_count FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;

    SELECT exists(
        SELECT 1 FROM auth.perm_set_perm psp
        INNER JOIN auth.permission p ON p.permission_id = psp.permission_id
        WHERE psp.perm_set_id = __perm_set_id AND p.full_code = 'fs_test_root.fs_child_a'::ltree
    ) INTO __has_a;

    IF __perm_count = 1 AND __has_a THEN
        RAISE NOTICE '  PASS: Within-set permissions synced (count=%, has_a=%)', __perm_count, __has_a;
    ELSE
        RAISE EXCEPTION '  FAIL: Within-set sync failed (count=%, has_a=%)', __perm_count, __has_a;
    END IF;
END $$;
