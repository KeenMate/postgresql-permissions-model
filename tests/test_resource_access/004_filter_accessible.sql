set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Filter accessible resources — mixed grants
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result bigint[];
BEGIN
    RAISE NOTICE 'TEST 1: Filter accessible resources with mixed grants';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read on documents 1001, 1002, 1003 (skip 1004, 1005)
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-filter-1a', 'document', 1001,
        _target_user_id := __user_id_2, _access_flags := array['read']);
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-filter-1b', 'document', 1002,
        _target_user_id := __user_id_2, _access_flags := array['read']);
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-filter-1c', 'document', 1003,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    -- Filter: ask for 1001-1005, should only get 1001, 1002, 1003
    SELECT array_agg(__resource_id order by __resource_id)
    FROM auth.filter_accessible_resources(__user_id_2, 'test-corr-filter-1d', 'document',
        array[1001, 1002, 1003, 1004, 1005]::bigint[], 'read')
    INTO __result;

    IF __result = array[1001, 1002, 1003]::bigint[] THEN
        RAISE NOTICE '  PASS: Filtered to accessible resources (%)', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {1001,1002,1003}, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Filter with deny — denied resources excluded
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result bigint[];
BEGIN
    RAISE NOTICE 'TEST 2: Filter with deny excludes denied resources';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Deny read on document 1002 for user_2
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-corr-filter-2a', 'document', 1002,
        __user_id_2, _access_flags := array['read']);

    -- Filter again
    SELECT array_agg(__resource_id order by __resource_id)
    FROM auth.filter_accessible_resources(__user_id_2, 'test-corr-filter-2b', 'document',
        array[1001, 1002, 1003, 1004, 1005]::bigint[], 'read')
    INTO __result;

    IF __result = array[1001, 1003]::bigint[] THEN
        RAISE NOTICE '  PASS: Denied resource excluded from filter (%)', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {1001,1003}, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Filter with group grants
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __result bigint[];
BEGIN
    RAISE NOTICE 'TEST 3: Filter includes resources from group grants';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read on document 1004 to editors group (user_2 is a member)
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-filter-3a', 'document', 1004,
        _user_group_id := __group_id_1, _access_flags := array['read']);

    -- Filter: should now include 1001, 1003 (direct) + 1004 (group), but not 1002 (denied)
    SELECT array_agg(__resource_id order by __resource_id)
    FROM auth.filter_accessible_resources(__user_id_2, 'test-corr-filter-3b', 'document',
        array[1001, 1002, 1003, 1004, 1005]::bigint[], 'read')
    INTO __result;

    IF __result = array[1001, 1003, 1004]::bigint[] THEN
        RAISE NOTICE '  PASS: Group grant included in filter (%)', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {1001,1003,1004}, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: System user sees all resources
-- ============================================================================
DO $$
DECLARE
    __result bigint[];
BEGIN
    RAISE NOTICE 'TEST 4: System user sees all resources in filter';

    SELECT array_agg(__resource_id order by __resource_id)
    FROM auth.filter_accessible_resources(1, 'test-corr-filter-4', 'document',
        array[1001, 1002, 1003, 1004, 1005]::bigint[], 'read')
    INTO __result;

    IF __result = array[1001, 1002, 1003, 1004, 1005]::bigint[] THEN
        RAISE NOTICE '  PASS: System user sees all resources (%)', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected all 5 resources, got %', __result;
    END IF;
END $$;
