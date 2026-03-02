set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Create hierarchy of permissions (root + children)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count          int;
    __has_projects   boolean;
    __has_create     boolean;
    __has_read       boolean;
BEGIN
    RAISE NOTICE 'TEST 1: ensure_permissions - create hierarchy (root + children)';

    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Projects", "is_assignable": false},
            {"title": "Create project", "parent_code": "test_projects"},
            {"title": "Read projects", "parent_code": "test_projects"},
            {"title": "Delete project", "parent_code": "test_projects"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT count(*) INTO __count
    FROM auth.permission
    WHERE full_code::text like 'test_projects%' AND source = 'test_ef';

    SELECT
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'test_projects'::ltree),
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'test_projects.create_project'::ltree),
        exists(SELECT 1 FROM auth.permission WHERE full_code = 'test_projects.read_projects'::ltree)
    INTO __has_projects, __has_create, __has_read;

    IF __count = 4 AND __has_projects AND __has_create AND __has_read THEN
        RAISE NOTICE '  PASS: Created 4 permissions with correct hierarchy (count=%, root=%, create=%, read=%)', __count, __has_projects, __has_create, __has_read;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 4 permissions with hierarchy (count=%, root=%, create=%, read=%)', __count, __has_projects, __has_create, __has_read;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: ensure_permissions is idempotent - no duplicates on re-call
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __count_before   int;
    __count_after    int;
    __returned       int;
BEGIN
    RAISE NOTICE 'TEST 2: ensure_permissions - idempotent (no duplicates on re-call)';

    SELECT count(*) INTO __count_before
    FROM auth.permission
    WHERE full_code::text like 'test_projects%';

    SELECT count(*) INTO __returned
    FROM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Projects", "is_assignable": false},
            {"title": "Create project", "parent_code": "test_projects"},
            {"title": "Read projects", "parent_code": "test_projects"},
            {"title": "Delete project", "parent_code": "test_projects"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT count(*) INTO __count_after
    FROM auth.permission
    WHERE full_code::text like 'test_projects%';

    IF __count_before = __count_after AND __returned = 4 THEN
        RAISE NOTICE '  PASS: Idempotent - no duplicates (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    ELSE
        RAISE EXCEPTION '  FAIL: Not idempotent (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Mix of existing and new permissions
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __has_update     boolean;
BEGIN
    RAISE NOTICE 'TEST 3: ensure_permissions - mix of existing and new';

    SELECT count(*) INTO __returned
    FROM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Projects", "is_assignable": false},
            {"title": "Create project", "parent_code": "test_projects"},
            {"title": "Update project", "parent_code": "test_projects"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT exists(SELECT 1 FROM auth.permission WHERE full_code = 'test_projects.update_project'::ltree)
    INTO __has_update;

    IF __returned = 3 AND __has_update THEN
        RAISE NOTICE '  PASS: Mix of existing+new works (returned=%, new_update=%)', __returned, __has_update;
    ELSE
        RAISE EXCEPTION '  FAIL: Mix of existing+new failed (returned=%, new_update=%)', __returned, __has_update;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Custom short_code and per-item source
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __short_code     text;
    __source         text;
BEGIN
    RAISE NOTICE 'TEST 4: ensure_permissions - custom short_code and source';

    PERFORM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Archive project", "parent_code": "test_projects", "short_code": "prj_arch", "source": "custom_source"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT p.short_code, p.source
    FROM auth.permission p
    WHERE p.full_code = 'test_projects.archive_project'::ltree
    INTO __short_code, __source;

    IF __short_code = 'prj_arch' AND __source = 'custom_source' THEN
        RAISE NOTICE '  PASS: Custom short_code=% and per-item source=%', __short_code, __source;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected short_code=prj_arch/source=custom_source, got short_code=%/source=%', __short_code, __source;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Deep hierarchy (grandchild permission)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __has_gdpr       boolean;
BEGIN
    RAISE NOTICE 'TEST 5: ensure_permissions - deep hierarchy (grandchild)';

    SELECT count(*) INTO __returned
    FROM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Read gdpr data", "parent_code": "test_projects.read_projects"}
        ]'::jsonb,
        'test_ef'
    );

    SELECT exists(SELECT 1 FROM auth.permission WHERE full_code = 'test_projects.read_projects.read_gdpr_data'::ltree)
    INTO __has_gdpr;

    IF __returned = 1 AND __has_gdpr THEN
        RAISE NOTICE '  PASS: Deep hierarchy grandchild created (returned=%, exists=%)', __returned, __has_gdpr;
    ELSE
        RAISE EXCEPTION '  FAIL: Deep hierarchy grandchild failed (returned=%, exists=%)', __returned, __has_gdpr;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: is_assignable=false is respected
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __is_assignable  boolean;
BEGIN
    RAISE NOTICE 'TEST 6: ensure_permissions - is_assignable=false respected';

    SELECT p.is_assignable
    FROM auth.permission p
    WHERE p.full_code = 'test_projects'::ltree
    INTO __is_assignable;

    IF __is_assignable = false THEN
        RAISE NOTICE '  PASS: Root permission is_assignable=false as specified';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected is_assignable=false, got %', __is_assignable;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Function-level source used when per-item source not provided
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __source         text;
BEGIN
    RAISE NOTICE 'TEST 7: ensure_permissions - function-level source as fallback';

    SELECT p.source
    FROM auth.permission p
    WHERE p.full_code = 'test_projects.create_project'::ltree
    INTO __source;

    IF __source = 'test_ef' THEN
        RAISE NOTICE '  PASS: Function-level source used as fallback (source=%)', __source;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected source=test_ef, got %', __source;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: Return set includes all requested items (existing + new)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __total          int;
BEGIN
    RAISE NOTICE 'TEST 8: ensure_permissions - returns all items (existing + new)';

    -- At this point we have: test_projects, create_project, read_projects, delete_project, update_project, archive_project, read_gdpr_data = 7
    SELECT count(*) INTO __total
    FROM auth.permission WHERE full_code::text like 'test_projects%';

    SELECT count(*) INTO __returned
    FROM auth.ensure_permissions(
        'test_ef', __user_id, __correlation_id,
        '[
            {"title": "Test Projects", "is_assignable": false},
            {"title": "Create project", "parent_code": "test_projects"},
            {"title": "Share project", "parent_code": "test_projects"}
        ]'::jsonb,
        'test_ef'
    );

    -- Should return 3: test_projects (existing), create_project (existing), share_project (new)
    IF __returned = 3 THEN
        RAISE NOTICE '  PASS: Returns all requested items including existing (returned=%)', __returned;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 returned, got %', __returned;
    END IF;
END $$;
