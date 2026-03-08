set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Grant with invalid flag for typed resource raises 35006
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __raised boolean := false;
    __sqlstate text;
BEGIN
    RAISE NOTICE 'TEST 1: Grant with invalid flag for typed resource raises 35006';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- 'folder' allows: read, write, delete, share
    -- 'approve' is NOT in folder's flag list → should raise 35006
    BEGIN
        PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-1', 'folder',
            '{"id": 500}'::jsonb,
            _target_user_id := __user_id_2, _access_flags := array['approve']);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __sqlstate = RETURNED_SQLSTATE;
        __raised := true;
    END;

    IF __raised AND __sqlstate = '35006' THEN
        RAISE NOTICE '  PASS: Grant with invalid flag raised 35006';
    ELSIF __raised THEN
        RAISE EXCEPTION '  FAIL: Expected 35006, got %', __sqlstate;
    ELSE
        RAISE EXCEPTION '  FAIL: Grant with invalid flag did not raise an error';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Deny with invalid flag for typed resource raises 35006
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __raised boolean := false;
    __sqlstate text;
BEGIN
    RAISE NOTICE 'TEST 2: Deny with invalid flag for typed resource raises 35006';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- 'folder' does not allow 'export' → should raise 35006
    BEGIN
        PERFORM auth.deny_resource_access('test', __user_id_1, 'test-ptf-2', 'folder',
            '{"id": 500}'::jsonb,
            __user_id_2, array['export']);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __sqlstate = RETURNED_SQLSTATE;
        __raised := true;
    END;

    IF __raised AND __sqlstate = '35006' THEN
        RAISE NOTICE '  PASS: Deny with invalid flag raised 35006';
    ELSIF __raised THEN
        RAISE EXCEPTION '  FAIL: Expected 35006, got %', __sqlstate;
    ELSE
        RAISE EXCEPTION '  FAIL: Deny with invalid flag did not raise an error';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Grant with valid flags succeeds
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 3: Grant with valid flags succeeds';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- 'document' allows: read, write, delete, share, export
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-3', 'document',
        '{"id": 600}'::jsonb,
        _target_user_id := __user_id_2, _access_flags := array['read', 'export']);

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document'
      AND resource_id = '{"id": 600}'::jsonb
      AND user_id = __user_id_2
      AND is_deny = false
    INTO __count;

    IF __count = 2 THEN
        RAISE NOTICE '  PASS: Grant with valid flags created 2 rows';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 grant rows, got %', __count;
    END IF;

    -- Cleanup
    PERFORM auth.revoke_resource_access('test', __user_id_1, 'test-ptf-3', 'document',
        '{"id": 600}'::jsonb, _target_user_id := __user_id_2);
END $$;

-- ============================================================================
-- TEST 4: Mixed valid + invalid flags — entire grant fails
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __raised boolean := false;
    __sqlstate text;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 4: Mixed valid + invalid flags — entire grant fails';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- 'folder' allows read, write, delete, share — NOT approve
    BEGIN
        PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-4', 'folder',
            '{"id": 700}'::jsonb,
            _target_user_id := __user_id_2, _access_flags := array['read', 'approve']);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __sqlstate = RETURNED_SQLSTATE;
        __raised := true;
    END;

    IF __raised AND __sqlstate = '35006' THEN
        RAISE NOTICE '  PASS: Mixed flags raised 35006';
    ELSIF __raised THEN
        RAISE EXCEPTION '  FAIL: Expected 35006, got %', __sqlstate;
    ELSE
        RAISE EXCEPTION '  FAIL: Mixed valid + invalid flags did not raise an error';
    END IF;

    -- Verify no partial writes occurred
    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'folder'
      AND resource_id = '{"id": 700}'::jsonb
      AND user_id = __user_id_2
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: No partial grant rows created';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 rows after failed grant, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Type with no flag mappings allows all flags (backward compat)
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 5: Type with no flag mappings allows all flags (backward compat)';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Create a resource type with NO per-type flag mappings
    INSERT INTO const.resource_type (code, title, description, source, parent_code, path, key_schema)
    VALUES ('ptf_untyped', 'PTF Untyped', 'Type with no flag mappings', 'test', null,
        'ptf_untyped'::ext.ltree, '{"id": "bigint"}'::jsonb)
    ON CONFLICT DO NOTHING;

    PERFORM unsecure.ensure_resource_access_partition('ptf_untyped');

    -- Should be able to grant ANY flag (including approve, export, etc.)
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-5', 'ptf_untyped',
        '{"id": 800}'::jsonb,
        _target_user_id := __user_id_2, _access_flags := array['read', 'approve', 'export']);

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'ptf_untyped'
      AND resource_id = '{"id": 800}'::jsonb
      AND user_id = __user_id_2
    INTO __count;

    IF __count = 3 THEN
        RAISE NOTICE '  PASS: Untyped resource accepted all 3 flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 grant rows, got %', __count;
    END IF;

    -- Cleanup
    PERFORM auth.revoke_resource_access('test', __user_id_1, 'test-ptf-5', 'ptf_untyped',
        '{"id": 800}'::jsonb, _target_user_id := __user_id_2);
END $$;

-- ============================================================================
-- TEST 6: get_resource_types returns access_flags
-- ============================================================================
DO $$
DECLARE
    __flags text[];
    __flag_count integer;
BEGIN
    RAISE NOTICE 'TEST 6: get_resource_types returns access_flags';

    -- 'document' has 5 flags: read, write, delete, share, export
    SELECT __access_flags FROM auth.get_resource_types()
    WHERE __code = 'document'
    INTO __flags;

    __flag_count := array_length(__flags, 1);

    IF __flag_count = 5 THEN
        RAISE NOTICE '  PASS: document type returned 5 access_flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 5 flags for document, got % (%)', __flag_count, __flags;
    END IF;

    -- 'folder' has 4 flags: read, write, delete, share
    SELECT __access_flags FROM auth.get_resource_types()
    WHERE __code = 'folder'
    INTO __flags;

    __flag_count := array_length(__flags, 1);

    IF __flag_count = 4 THEN
        RAISE NOTICE '  PASS: folder type returned 4 access_flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 4 flags for folder, got % (%)', __flag_count, __flags;
    END IF;

    -- 'ptf_untyped' has no mappings → should return null
    SELECT __access_flags FROM auth.get_resource_types()
    WHERE __code = 'ptf_untyped'
    INTO __flags;

    IF __flags IS NULL THEN
        RAISE NOTICE '  PASS: Untyped resource returned null access_flags';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected null flags for untyped, got %', __flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: ensure_resource_types registers per-type flags
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __flag_count integer;
    __flags text[];
BEGIN
    RAISE NOTICE 'TEST 7: ensure_resource_types registers per-type flags';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Register a new type via ensure_resource_types with access_flags
    PERFORM auth.ensure_resource_types('test', __user_id_1, 'test-ptf-7', '[
        {"code": "ptf_ensured", "title": "PTF Ensured",
         "key_schema": {"id": "bigint"},
         "access_flags": ["read", "write", "approve"]}
    ]'::jsonb, _source := 'test');

    -- Verify flags in const.resource_type_flag
    SELECT count(*) FROM const.resource_type_flag
    WHERE resource_type_code = 'ptf_ensured'
    INTO __flag_count;

    IF __flag_count = 3 THEN
        RAISE NOTICE '  PASS: ensure_resource_types created 3 flag mappings';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 flag mappings, got %', __flag_count;
    END IF;

    -- Verify via get_resource_types
    SELECT __access_flags FROM auth.get_resource_types()
    WHERE __code = 'ptf_ensured'
    INTO __flags;

    IF array_length(__flags, 1) = 3 THEN
        RAISE NOTICE '  PASS: get_resource_types returns 3 flags for ensured type';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 flags from get_resource_types, got %', __flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: create_resource_type registers per-type flags
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __flag_count integer;
BEGIN
    RAISE NOTICE 'TEST 8: create_resource_type registers per-type flags';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    PERFORM auth.create_resource_type('test', __user_id_1, 'test-ptf-8',
        'ptf_created', 'PTF Created',
        _key_schema := '{"id": "bigint"}'::jsonb,
        _access_flags := array['read', 'delete'],
        _source := 'test');

    SELECT count(*) FROM const.resource_type_flag
    WHERE resource_type_code = 'ptf_created'
    INTO __flag_count;

    IF __flag_count = 2 THEN
        RAISE NOTICE '  PASS: create_resource_type created 2 flag mappings';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flag mappings, got %', __flag_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: Hierarchical types — child type validates its own flags
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __raised boolean := false;
    __sqlstate text;
BEGIN
    RAISE NOTICE 'TEST 9: Hierarchical types — child type validates its own flags';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- 'project' allows: read, write, delete, share
    -- 'project.invoices' allows: read, write, approve
    -- Granting 'share' on project.invoices should fail (share is valid for project, not invoices)
    BEGIN
        PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-9', 'project.invoices',
            '{"project_id": 9000, "invoice_id": 1}'::jsonb,
            _target_user_id := __user_id_2, _access_flags := array['share']);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __sqlstate = RETURNED_SQLSTATE;
        __raised := true;
    END;

    IF __raised AND __sqlstate = '35006' THEN
        RAISE NOTICE '  PASS: Child type rejects parent-only flag (share on invoices)';
    ELSIF __raised THEN
        RAISE EXCEPTION '  FAIL: Expected 35006, got %', __sqlstate;
    ELSE
        RAISE EXCEPTION '  FAIL: Child type accepted parent-only flag';
    END IF;
END $$;

-- ============================================================================
-- TEST 10: Matrix respects per-type flags for system user
-- ============================================================================
DO $$
DECLARE
    __count integer;
    __expected integer;
BEGIN
    RAISE NOTICE 'TEST 10: Matrix respects per-type flags for system user';

    -- System user (id=1) gets all flags, but only the ones valid for each type
    -- project: read, write, delete, share = 4
    -- project.documents: read, write, delete, export = 4
    -- project.invoices: read, write, approve = 3
    -- Total = 11
    SELECT count(*)
    FROM auth.get_resource_access_matrix(1, 'test-ptf-10', 'project', '{"project_id": 9999}'::jsonb)
    INTO __count;

    SELECT coalesce(sum(flag_count), 0)::integer
    FROM (
        SELECT rt.code,
            (SELECT count(*) FROM const.resource_type_flag rtf WHERE rtf.resource_type_code = rt.code) as flag_count
        FROM const.resource_type rt
        WHERE rt.path <@ 'project'::ext.ltree AND rt.is_active = true
    ) sub
    INTO __expected;

    IF __count = __expected THEN
        RAISE NOTICE '  PASS: System user matrix has % entries (per-type flag count)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected % entries for system user matrix, got %', __expected, __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: Grant valid child-specific flag succeeds
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 11: Grant valid child-specific flag succeeds';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    -- 'project.invoices' allows 'approve' — a flag NOT on the parent 'project'
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-ptf-11', 'project.invoices',
        '{"project_id": 9000, "invoice_id": 1}'::jsonb,
        _target_user_id := __user_id_3, _access_flags := array['approve']);

    __has_access := auth.has_resource_access(__user_id_3, 'test-ptf-11', 'project.invoices',
        '{"project_id": 9000, "invoice_id": 1}'::jsonb, 'approve', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Grant with child-specific flag (approve on invoices) works';
    ELSE
        RAISE EXCEPTION '  FAIL: Grant with child-specific flag did not work';
    END IF;

    -- Cleanup
    PERFORM auth.revoke_resource_access('test', __user_id_1, 'test-ptf-11', 'project.invoices',
        '{"project_id": 9000, "invoice_id": 1}'::jsonb, _target_user_id := __user_id_3);
END $$;

-- ============================================================================
-- Cleanup test-specific resource types
-- ============================================================================
DO $$
BEGIN
    DELETE FROM auth.resource_access WHERE root_type IN ('ptf_untyped', 'ptf_ensured', 'ptf_created');
    DELETE FROM const.resource_type_flag WHERE resource_type_code IN ('ptf_untyped', 'ptf_ensured', 'ptf_created');
    DELETE FROM const.resource_type WHERE code IN ('ptf_untyped', 'ptf_ensured', 'ptf_created') AND source = 'test';
    RAISE NOTICE '  Cleanup: per-type flag test types removed';
END $$;
