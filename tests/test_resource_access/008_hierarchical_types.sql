set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Register parent + child types
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __rt record;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 1: Register parent + child types';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    -- Create root type 'project' (code = hierarchy path for root types)
    INSERT INTO const.resource_type (code, title, description, source, parent_code, path)
    VALUES ('project', 'Project', 'Test project root type', 'test', null, 'project'::ext.ltree)
    ON CONFLICT DO NOTHING;

    PERFORM unsecure.ensure_resource_access_partition('project');

    -- Create child types (code uses dots to encode hierarchy)
    INSERT INTO const.resource_type (code, title, description, source, parent_code, path)
    VALUES ('project.documents', 'Project Documents', 'Documents sub-type', 'test', 'project', 'project.documents'::ext.ltree)
    ON CONFLICT DO NOTHING;

    INSERT INTO const.resource_type (code, title, description, source, parent_code, path)
    VALUES ('project.invoices', 'Project Invoices', 'Invoices sub-type', 'test', 'project', 'project.invoices'::ext.ltree)
    ON CONFLICT DO NOTHING;

    -- Children share parent's partition (ensure_resource_access_partition extracts root via split_part)
    PERFORM unsecure.ensure_resource_access_partition('project.documents');
    PERFORM unsecure.ensure_resource_access_partition('project.invoices');

    -- Verify types exist
    SELECT count(*) FROM const.resource_type
    WHERE code IN ('project', 'project.documents', 'project.invoices')
    INTO __count;

    IF __count = 3 THEN
        RAISE NOTICE '  PASS: 3 hierarchical resource types created';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 types, got %', __count;
    END IF;

    -- Verify hierarchy via ltree: project is ancestor of project.documents
    SELECT count(*) FROM const.resource_type
    WHERE path <@ 'project'::ext.ltree
    INTO __count;

    IF __count = 3 THEN
        RAISE NOTICE '  PASS: ltree hierarchy correct (3 types under project)';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 types under project, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Grant on parent, child inherits read access
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Grant on parent, child inherits read access';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read on 'project' (parent) for resource_id 1000
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-hier-2', 'project', 1000,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    -- Check child type access — should inherit from parent
    __has_access := auth.has_resource_access(__user_id_2, 'test-hier-2', 'project.documents', 1000,
        'read', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Child type inherited read from parent grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Child type did NOT inherit read from parent grant';
    END IF;

    -- Also check the other child type
    __has_access := auth.has_resource_access(__user_id_2, 'test-hier-2', 'project.invoices', 1000,
        'read', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Second child type also inherited read from parent grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Second child type did NOT inherit read from parent';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Direct child grant works independently
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_3 bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 3: Direct child grant works independently';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_3' INTO __user_id_3;

    -- Grant write only on child type for user_3
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-hier-3', 'project.documents', 1000,
        _target_user_id := __user_id_3, _access_flags := array['write']);

    -- User 3 should have write on project.documents
    __has_access := auth.has_resource_access(__user_id_3, 'test-hier-3', 'project.documents', 1000,
        'write', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Direct child grant works (write on project.documents)';
    ELSE
        RAISE EXCEPTION '  FAIL: Direct child grant did not work';
    END IF;

    -- User 3 should NOT have write on parent (grant doesn't propagate up)
    __has_access := auth.has_resource_access(__user_id_3, 'test-hier-3', 'project', 1000,
        'write', 1, false);

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Child grant does NOT propagate up to parent';
    ELSE
        RAISE EXCEPTION '  FAIL: Child grant incorrectly propagated up to parent';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Deny on child overrides parent grant
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Deny on child overrides parent grant';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- User 2 already has read on 'project' from TEST 2
    -- Deny read on specific child type
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-hier-4', 'project.invoices', 1000,
        __user_id_2, array['read']);

    -- User 2 should NOT have read on project.invoices (deny overrides parent grant)
    __has_access := auth.has_resource_access(__user_id_2, 'test-hier-4', 'project.invoices', 1000,
        'read', 1, false);

    IF NOT __has_access THEN
        RAISE NOTICE '  PASS: Deny on child overrides parent grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Deny on child did NOT override parent grant';
    END IF;

    -- User 2 should still have read on project.documents (deny only on invoices)
    __has_access := auth.has_resource_access(__user_id_2, 'test-hier-4', 'project.documents', 1000,
        'read', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Deny on one child does not affect sibling';
    ELSE
        RAISE EXCEPTION '  FAIL: Deny on invoices incorrectly affected documents';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Group grant on parent cascades to child
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __has_access boolean;
BEGIN
    RAISE NOTICE 'TEST 5: Group grant on parent cascades to child';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant write on 'project' to group (user_2 is member of group_id_1)
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-hier-5', 'project', 2000,
        _user_group_id := __group_id_1, _access_flags := array['write']);

    -- User 2 (member of editors group) should inherit write on child via group + hierarchy
    __has_access := auth.has_resource_access(__user_id_2, 'test-hier-5', 'project.documents', 2000,
        'write', 1, false);

    IF __has_access THEN
        RAISE NOTICE '  PASS: Group grant on parent cascades to child';
    ELSE
        RAISE EXCEPTION '  FAIL: Group grant on parent did NOT cascade to child';
    END IF;
END $$;
