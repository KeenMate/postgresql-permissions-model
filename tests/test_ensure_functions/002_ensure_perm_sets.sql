set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 9: Create new perm set with permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __perm_count     int;
    __perm_set_id    int;
BEGIN
    RAISE NOTICE 'TEST 9: ensure_perm_sets - create new perm set with permissions';

    -- First ensure we have the test permissions
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Projects", "is_assignable": false},
            {"title": "Create project", "parent_code": "test_projects"},
            {"title": "Read projects", "parent_code": "test_projects"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT count(*) INTO __returned
    FROM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Project User", "permissions": ["test_projects.create_project", "test_projects.read_projects"]}
        ]'::jsonb,
        'test_ef'
    );

    SELECT ps.perm_set_id
    FROM auth.perm_set ps
    WHERE ps.code = 'test_project_user' AND ps.tenant_id = 1
    INTO __perm_set_id;

    SELECT count(*)
    FROM auth.perm_set_perm psp
    WHERE psp.perm_set_id = __perm_set_id
    INTO __perm_count;

    IF __returned = 1 AND __perm_set_id IS NOT NULL AND __perm_count = 2 THEN
        RAISE NOTICE '  PASS: Created perm set with permissions (returned=%, perm_set_id=%, perm_count=%)', __returned, __perm_set_id, __perm_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Perm set creation failed (returned=%, perm_set_id=%, perm_count=%)', __returned, __perm_set_id, __perm_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: ensure_perm_sets is idempotent - no duplicate perm sets or permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
    __perm_before    int;
    __perm_after     int;
    __perm_set_id    int;
BEGIN
    RAISE NOTICE 'TEST 10: ensure_perm_sets - idempotent (no duplicates on re-call)';

    SELECT ps.perm_set_id
    FROM auth.perm_set ps
    WHERE ps.code = 'test_project_user' AND ps.tenant_id = 1
    INTO __perm_set_id;

    SELECT count(*) INTO __count_before FROM auth.perm_set WHERE code = 'test_project_user' AND tenant_id = 1;
    SELECT count(*) INTO __perm_before FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;

    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Project User", "permissions": ["test_projects.create_project", "test_projects.read_projects"]}
        ]'::jsonb,
        'test_ef'
    );

    SELECT count(*) INTO __count_after FROM auth.perm_set WHERE code = 'test_project_user' AND tenant_id = 1;
    SELECT count(*) INTO __perm_after FROM auth.perm_set_perm WHERE perm_set_id = __perm_set_id;

    IF __count_before = __count_after AND __perm_before = __perm_after THEN
        RAISE NOTICE '  PASS: Idempotent - no duplicates (sets: before=%, after=%; perms: before=%, after=%)', __count_before, __count_after, __perm_before, __perm_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Not idempotent (sets: before=%, after=%; perms: before=%, after=%)', __count_before, __count_after, __perm_before, __perm_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: Existing perm set with new permissions - adds missing permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __perm_count     int;
    __perm_set_id    int;
BEGIN
    RAISE NOTICE 'TEST 11: ensure_perm_sets - existing perm set gets new permissions added';

    -- Ensure we have the delete_project permission
    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "Delete project", "parent_code": "test_projects"}]'::jsonb,
        'test_ef'
    );

    -- Call ensure_perm_sets with existing set + new permission
    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Project User", "permissions": ["test_projects.create_project", "test_projects.read_projects", "test_projects.delete_project"]}
        ]'::jsonb,
        'test_ef'
    );

    SELECT ps.perm_set_id
    FROM auth.perm_set ps
    WHERE ps.code = 'test_project_user' AND ps.tenant_id = 1
    INTO __perm_set_id;

    SELECT count(*)
    FROM auth.perm_set_perm psp
    WHERE psp.perm_set_id = __perm_set_id
    INTO __perm_count;

    -- Should now have 3 permissions (2 original + 1 new)
    IF __perm_count = 3 THEN
        RAISE NOTICE '  PASS: New permission added to existing perm set (perm_count=%)', __perm_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 permissions, got %', __perm_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: Multiple perm sets in one call
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __viewer_exists  boolean;
    __editor_exists  boolean;
BEGIN
    RAISE NOTICE 'TEST 12: ensure_perm_sets - multiple perm sets in one call';

    SELECT count(*) INTO __returned
    FROM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Project Viewer", "permissions": ["test_projects.read_projects"]},
            {"title": "Test Project Editor", "permissions": ["test_projects.create_project", "test_projects.read_projects", "test_projects.delete_project"]}
        ]'::jsonb,
        'test_ef'
    );

    SELECT
        exists(SELECT 1 FROM auth.perm_set WHERE code = 'test_project_viewer' AND tenant_id = 1),
        exists(SELECT 1 FROM auth.perm_set WHERE code = 'test_project_editor' AND tenant_id = 1)
    INTO __viewer_exists, __editor_exists;

    IF __returned = 2 AND __viewer_exists AND __editor_exists THEN
        RAISE NOTICE '  PASS: Multiple perm sets created (returned=%, viewer=%, editor=%)', __returned, __viewer_exists, __editor_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Multiple perm sets failed (returned=%, viewer=%, editor=%)', __returned, __viewer_exists, __editor_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: Perm set with is_system and is_assignable flags
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __is_assignable  boolean;
    __source         text;
BEGIN
    RAISE NOTICE 'TEST 13: ensure_perm_sets - is_assignable=false and custom source';

    PERFORM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Internal Set", "is_assignable": false, "source": "internal_module", "permissions": ["test_projects.read_projects"]}
        ]'::jsonb,
        'test_ef'
    );

    SELECT ps.is_assignable, ps.source
    FROM auth.perm_set ps
    WHERE ps.code = 'test_internal_set' AND ps.tenant_id = 1
    INTO __is_assignable, __source;

    IF __is_assignable = false AND __source = 'internal_module' THEN
        RAISE NOTICE '  PASS: Flags respected (is_assignable=%, source=%)', __is_assignable, __source;
    ELSE
        RAISE EXCEPTION '  FAIL: Flags not respected (is_assignable=%, source=%)', __is_assignable, __source;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: Perm set with empty permissions array
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __perm_count     int;
    __perm_set_id    int;
BEGIN
    RAISE NOTICE 'TEST 14: ensure_perm_sets - perm set with no permissions';

    SELECT count(*) INTO __returned
    FROM auth.ensure_perm_sets(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Empty Set", "permissions": []}
        ]'::jsonb,
        'test_ef'
    );

    SELECT ps.perm_set_id
    FROM auth.perm_set ps
    WHERE ps.code = 'test_empty_set' AND ps.tenant_id = 1
    INTO __perm_set_id;

    SELECT count(*)
    FROM auth.perm_set_perm psp
    WHERE psp.perm_set_id = __perm_set_id
    INTO __perm_count;

    IF __returned = 1 AND __perm_set_id IS NOT NULL AND __perm_count = 0 THEN
        RAISE NOTICE '  PASS: Empty perm set created (returned=%, perm_set_id=%, perm_count=%)', __returned, __perm_set_id, __perm_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Empty perm set failed (returned=%, perm_set_id=%, perm_count=%)', __returned, __perm_set_id, __perm_count;
    END IF;
END $$;
