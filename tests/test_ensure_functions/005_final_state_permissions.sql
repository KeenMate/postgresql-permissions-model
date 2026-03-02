set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 27: _is_final_state=true with null source raises error
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
BEGIN
    RAISE NOTICE 'TEST 27: ensure_permissions - final_state with null source raises error';

    BEGIN
        PERFORM auth.ensure_permissions(
            'test_ef', __user_id, __correlation_id,
            '[{"title": "Dummy Perm"}]'::jsonb,
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
-- TEST 28: _is_final_state=false (default) does NOT remove anything
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
BEGIN
    RAISE NOTICE 'TEST 28: ensure_permissions - default (no final_state) does NOT remove';

    -- Create 3 permissions with source 'fs_test'
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false},
            {"title": "FS Child A", "parent_code": "fs_test_root"},
            {"title": "FS Child B", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test'
    );

    SELECT count(*) INTO __count_before
    FROM auth.permission WHERE source = 'fs_test';

    -- Call with only 1 item, but _is_final_state defaults to false
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false}
        ]'::jsonb,
        'fs_test'
    );

    SELECT count(*) INTO __count_after
    FROM auth.permission WHERE source = 'fs_test';

    IF __count_before = __count_after AND __count_after = 3 THEN
        RAISE NOTICE '  PASS: Default mode did not remove anything (before=%, after=%)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Default mode should not remove (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 29: _is_final_state=true removes unlisted same-source permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count          int;
    __has_root       boolean;
    __has_a          boolean;
    __has_b          boolean;
BEGIN
    RAISE NOTICE 'TEST 29: ensure_permissions - final_state removes unlisted same-source';

    -- Now call with only root + child_a, final_state=true => child_b should be removed
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false},
            {"title": "FS Child A", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test',
        true  -- _is_final_state
    );

    SELECT count(*) INTO __count FROM auth.permission WHERE source = 'fs_test';

    SELECT
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'fs_test_root'::ltree),
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'fs_test_root.fs_child_a'::ltree),
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'fs_test_root.fs_child_b'::ltree)
    INTO __has_root, __has_a, __has_b;

    IF __count = 2 AND __has_root AND __has_a AND NOT __has_b THEN
        RAISE NOTICE '  PASS: Final state removed child_b (count=%, root=%, a=%, b=%)', __count, __has_root, __has_a, __has_b;
    ELSE
        RAISE EXCEPTION '  FAIL: Final state removal wrong (count=%, root=%, a=%, b=%)', __count, __has_root, __has_a, __has_b;
    END IF;
END $$;

-- ============================================================================
-- TEST 30: _is_final_state=true does NOT remove different-source permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_other    int;
BEGIN
    RAISE NOTICE 'TEST 30: ensure_permissions - final_state does NOT remove different source';

    -- Create a permission with a different source
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "Other Source Perm"}]'::jsonb,
        'other_source'
    );

    -- Now run final state for 'fs_test' source
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false},
            {"title": "FS Child A", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test',
        true
    );

    SELECT count(*) INTO __count_other
    FROM auth.permission WHERE source = 'other_source';

    IF __count_other = 1 THEN
        RAISE NOTICE '  PASS: Different source permission untouched (count=%)', __count_other;
    ELSE
        RAISE EXCEPTION '  FAIL: Different source permission affected (count=%)', __count_other;
    END IF;
END $$;

-- ============================================================================
-- TEST 31: _is_final_state=true cleans up perm_set_perm and permission_assignment
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __perm_id        int;
    __perm_set_id    int;
    __psp_count      int;
    __pa_count       int;
    __perm_exists    boolean;
BEGIN
    RAISE NOTICE 'TEST 31: ensure_permissions - final_state cleans up references before deleting';

    -- Create a permission that will be removed
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Doomed Perm", "parent_code": "fs_test_root"}]'::jsonb,
        'fs_test'
    );

    SELECT permission_id INTO __perm_id
    FROM auth.permission WHERE full_code = 'fs_test_root.fs_doomed_perm'::ltree;

    -- Create a perm set and link the doomed permission to it
    INSERT INTO auth.perm_set (created_by, updated_by, tenant_id, title, code, source)
    VALUES ('test_ef', 'test_ef', 1, 'FS Doom Set', 'fs_doom_set', 'fs_test_ref')
    RETURNING perm_set_id INTO __perm_set_id;

    INSERT INTO auth.perm_set_perm (created_by, perm_set_id, permission_id)
    VALUES ('test_ef', __perm_set_id, __perm_id);

    -- Also add a permission_assignment referencing this permission directly
    INSERT INTO auth.permission_assignment (created_by, permission_id, user_id, tenant_id)
    VALUES ('test_ef', __perm_id, __user_id, 1);

    -- Now remove fs_doomed_perm via final_state
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "FS Test Root", "is_assignable": false},
            {"title": "FS Child A", "parent_code": "fs_test_root"}
        ]'::jsonb,
        'fs_test',
        true
    );

    SELECT count(*) INTO __psp_count
    FROM auth.perm_set_perm WHERE permission_id = __perm_id;

    SELECT count(*) INTO __pa_count
    FROM auth.permission_assignment WHERE permission_id = __perm_id;

    SELECT exists(SELECT 1 FROM auth.permission WHERE permission_id = __perm_id)
    INTO __perm_exists;

    IF NOT __perm_exists AND __psp_count = 0 AND __pa_count = 0 THEN
        RAISE NOTICE '  PASS: References cleaned up (perm_exists=%, psp=%, pa=%)', __perm_exists, __psp_count, __pa_count;
    ELSE
        RAISE EXCEPTION '  FAIL: References not cleaned (perm_exists=%, psp=%, pa=%)', __perm_exists, __psp_count, __pa_count;
    END IF;

    -- Cleanup the test perm_set
    DELETE FROM auth.perm_set WHERE perm_set_id = __perm_set_id;
END $$;
