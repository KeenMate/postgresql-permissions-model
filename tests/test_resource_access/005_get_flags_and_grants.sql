set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: get_resource_access_flags — direct grants
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __flags text[];
BEGIN
    RAISE NOTICE 'TEST 1: get_resource_access_flags returns direct grants';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read + write to user_2 on document 2001
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-flags-1a', 'document', 2001,
        _target_user_id := __user_id_2, _access_flags := array['read', 'write']);

    -- Get effective flags
    SELECT array_agg(__access_flag order by __access_flag)
    FROM auth.get_resource_access_flags(__user_id_2, 'test-corr-flags-1b', 'document', 2001)
    INTO __flags;

    IF __flags = array['read', 'write'] THEN
        RAISE NOTICE '  PASS: Effective flags: %', __flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {read,write}, got %', __flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: get_resource_access_flags — denied flag excluded
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __flags text[];
BEGIN
    RAISE NOTICE 'TEST 2: get_resource_access_flags excludes denied flags';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read+write+delete to group on document 2002
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-flags-2a', 'document', 2002,
        _user_group_id := __group_id_1, _access_flags := array['read', 'write', 'delete']);

    -- Deny write for user_2
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-corr-flags-2b', 'document', 2002,
        __user_id_2, _access_flags := array['write']);

    -- Get effective flags — should exclude 'write'
    SELECT array_agg(__access_flag order by __access_flag)
    FROM auth.get_resource_access_flags(__user_id_2, 'test-corr-flags-2c', 'document', 2002)
    INTO __flags;

    IF __flags = array['delete', 'read'] THEN
        RAISE NOTICE '  PASS: Denied flag excluded, effective: %', __flags;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {delete,read}, got %', __flags;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: get_resource_access_flags — source attribution
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __direct_count integer;
    __group_count integer;
BEGIN
    RAISE NOTICE 'TEST 3: get_resource_access_flags returns source attribution';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read directly to user_2 on document 2003
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-flags-3a', 'document', 2003,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    -- Grant write to group on document 2003
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-flags-3b', 'document', 2003,
        _user_group_id := __group_id_1, _access_flags := array['write']);

    -- Check sources
    SELECT count(*) FROM auth.get_resource_access_flags(__user_id_2, 'test-corr-flags-3c', 'document', 2003)
    WHERE __source = 'direct' INTO __direct_count;

    SELECT count(*) FROM auth.get_resource_access_flags(__user_id_2, 'test-corr-flags-3d', 'document', 2003)
    WHERE __source = 'RA Test Group Editors' INTO __group_count;

    IF __direct_count = 1 AND __group_count = 1 THEN
        RAISE NOTICE '  PASS: Source attribution correct (direct=%, group=%)', __direct_count, __group_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected direct=1, group=1, got direct=%, group=%', __direct_count, __group_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: get_resource_grants — lists all grants/denies for a resource
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __total_count integer;
    __deny_count integer;
BEGIN
    RAISE NOTICE 'TEST 4: get_resource_grants lists all grants and denies';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Document 2002 has: group grants (read, write, delete) + user deny (write)
    SELECT count(*) FROM auth.get_resource_grants(__user_id_1, 'test-corr-grants-4a', 'document', 2002)
    INTO __total_count;

    SELECT count(*) FROM auth.get_resource_grants(__user_id_1, 'test-corr-grants-4b', 'document', 2002)
    WHERE __is_deny = true INTO __deny_count;

    IF __total_count = 4 AND __deny_count = 1 THEN
        RAISE NOTICE '  PASS: Total grants=%, denies=%', __total_count, __deny_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected total=4, denies=1, got total=%, denies=%', __total_count, __deny_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: get_resource_grants — includes display names
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __has_user_name boolean;
    __has_group_name boolean;
BEGIN
    RAISE NOTICE 'TEST 5: get_resource_grants includes display names';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;

    SELECT exists(
        SELECT 1 FROM auth.get_resource_grants(__user_id_1, 'test-corr-grants-5a', 'document', 2002)
        WHERE __user_display_name IS NOT NULL
    ) INTO __has_user_name;

    SELECT exists(
        SELECT 1 FROM auth.get_resource_grants(__user_id_1, 'test-corr-grants-5b', 'document', 2002)
        WHERE __group_title IS NOT NULL
    ) INTO __has_group_name;

    IF __has_user_name AND __has_group_name THEN
        RAISE NOTICE '  PASS: Display names present for both users and groups';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected user_name=true, group_name=true, got %, %', __has_user_name, __has_group_name;
    END IF;
END $$;
