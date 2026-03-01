set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Matrix returns all sub-types with flags
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 1: Matrix returns all sub-types with flags';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- User 2 has read on 'project' (from 008 TEST 2) for resource 1000
    -- Matrix should show read inherited across all sub-types
    SELECT count(*)
    FROM auth.get_resource_access_matrix(__user_id_2, 'test-matrix-1', 'project', 1000)
    WHERE __access_flag = 'read'
    INTO __count;

    -- Should have read on project + project.documents (project.invoices is denied from 008 TEST 4)
    IF __count >= 2 THEN
        RAISE NOTICE '  PASS: Matrix returned read flag for >= 2 types (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 2 types with read flag, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Denied flags excluded from matrix
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 2: Denied flags excluded from matrix';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- User 2 has read denied on project.invoices (from 008 TEST 4)
    SELECT count(*)
    FROM auth.get_resource_access_matrix(__user_id_2, 'test-matrix-2', 'project', 1000)
    WHERE __resource_type = 'project.invoices' AND __access_flag = 'read'
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: Denied flag excluded from matrix';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 (denied flag should be excluded), got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: System user gets full matrix
-- ============================================================================
DO $$
DECLARE
    __count integer;
    __expected integer;
BEGIN
    RAISE NOTICE 'TEST 3: System user gets full matrix';

    -- System user (id=1) should get ALL types × ALL flags
    SELECT count(*)
    FROM auth.get_resource_access_matrix(1, 'test-matrix-3', 'project', 9999)
    INTO __count;

    -- 3 types × 4 flags = 12
    SELECT (SELECT count(*) FROM const.resource_type WHERE path <@ 'project'::ext.ltree AND is_active = true)
         * (SELECT count(*) FROM const.resource_access_flag)
    INTO __expected;

    IF __count = __expected THEN
        RAISE NOTICE '  PASS: System user gets full matrix (% entries)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected % entries for system user, got %', __expected, __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Inherited + direct flags combined
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __count_total integer;
    __has_parent_read boolean;
    __has_child_write boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Inherited + direct flags combined in matrix';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    -- Give user_3 read on parent project for resource 3000
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-matrix-4a', 'project', 3000,
        _target_user_id := __user_id_3, _access_flags := array['read']);

    -- Give user_3 write on project.documents only for resource 3000
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-matrix-4b', 'project.documents', 3000,
        _target_user_id := __user_id_3, _access_flags := array['write']);

    -- Matrix should show:
    -- project: read (direct)
    -- project.documents: read (inherited from project) + write (direct)
    -- project.invoices: read (inherited from project)

    SELECT count(*)
    FROM auth.get_resource_access_matrix(__user_id_3, 'test-matrix-4', 'project', 3000)
    INTO __count_total;

    -- At least 4 entries: project/read, project.documents/read, project.documents/write, project.invoices/read
    IF __count_total >= 4 THEN
        RAISE NOTICE '  PASS: Matrix has >= 4 entries with inherited + direct (count=%)', __count_total;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 4 entries, got %', __count_total;
    END IF;

    -- Check project.documents has both read (inherited) and write (direct)
    SELECT exists(
        SELECT 1 FROM auth.get_resource_access_matrix(__user_id_3, 'test-matrix-4', 'project', 3000)
        WHERE __resource_type = 'project.documents' AND __access_flag = 'read'
    ) INTO __has_parent_read;

    SELECT exists(
        SELECT 1 FROM auth.get_resource_access_matrix(__user_id_3, 'test-matrix-4', 'project', 3000)
        WHERE __resource_type = 'project.documents' AND __access_flag = 'write'
    ) INTO __has_child_write;

    IF __has_parent_read AND __has_child_write THEN
        RAISE NOTICE '  PASS: project.documents has both inherited read and direct write';
    ELSE
        RAISE EXCEPTION '  FAIL: project.documents missing flags (read=%, write=%)', __has_parent_read, __has_child_write;
    END IF;
END $$;
