set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: assign_api_key_permissions with perm_set_code
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __row_count int;
BEGIN
    RAISE NOTICE 'TEST 10: assign_api_key_permissions with perm_set_code';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';
    SELECT val::int INTO __api_key_id FROM _ak_test_data WHERE key = 'key1_id';

    -- Assign system_admin perm set to the api key
    SELECT count(*)
    FROM auth.assign_api_key_permissions(
        'ak_test', __admin_id, 'ak-test-assign',
        __api_key_id,
        'system_admin',
        null,
        1
    ) r
    INTO __row_count;

    IF __row_count > 0 THEN
        RAISE NOTICE '  PASS: assign_api_key_permissions returned % rows', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: assign_api_key_permissions returned 0 rows';
    END IF;
END $$;

-- ============================================================================
-- TEST 11: get_api_key_permissions returns 11 columns
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __row_count int;
    __col_count int;
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 11: get_api_key_permissions returns 11 columns';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';
    SELECT val::int INTO __api_key_id FROM _ak_test_data WHERE key = 'key1_id';

    -- Get first row to verify column structure
    SELECT r.__assignment_id, r.__perm_set_code, r.__perm_set_title,
           r.__user_group_member_id, r.__user_group_title,
           r.__permission_inheritance_type, r.__permission_code, r.__permission_title,
           r.__tenant_id, r.__tenant_code, r.__tenant_title
    FROM auth.get_api_key_permissions(__admin_id, 'ak-test-getperm', __api_key_id, 1) r
    LIMIT 1
    INTO __rec;

    -- Count total rows
    SELECT count(*)
    FROM auth.get_api_key_permissions(__admin_id, 'ak-test-getperm', __api_key_id, 1)
    INTO __row_count;

    IF __rec.__assignment_id IS NOT NULL AND __row_count > 0 THEN
        RAISE NOTICE '  PASS: get_api_key_permissions returned % rows, 11 columns verified (assignment_id=%, perm_set=%, perm=%)',
            __row_count, __rec.__assignment_id, __rec.__perm_set_code, __rec.__permission_code;
    ELSE
        RAISE EXCEPTION '  FAIL: get_api_key_permissions returned no data (row_count=%)', __row_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: assign_api_key_permissions with individual permission_codes
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __api_key text;
    __api_secret text;
    __new_key_id int;
    __row_count int;
BEGIN
    RAISE NOTICE 'TEST 12: assign_api_key_permissions with individual permission_codes';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    -- Create a fresh key for this test (no perm_set)
    SELECT r.__api_key_id, r.__api_key, r.__api_secret
    FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-indiv-perm',
        'Key With Individual Perms', 'For testing individual permission assignment',
        null, null, _tenant_id := 1
    ) r
    INTO __new_key_id, __api_key, __api_secret;

    -- Assign individual permissions
    SELECT count(*)
    FROM auth.assign_api_key_permissions(
        'ak_test', __admin_id, 'ak-test-indiv-assign',
        __new_key_id,
        null,
        array['users.read_users', 'users.read_all_users'],
        1
    ) r
    INTO __row_count;

    IF __row_count = 2 THEN
        RAISE NOTICE '  PASS: assigned 2 individual permissions (count=%)', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 2 permission rows, got %', __row_count;
    END IF;

    -- Store for cleanup
    INSERT INTO _ak_test_data VALUES ('key2_id', __new_key_id::text)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
END $$;

-- ============================================================================
-- TEST 13: unassign_api_key_permissions removes perm_set
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __remaining int;
BEGIN
    RAISE NOTICE 'TEST 13: unassign_api_key_permissions removes perm_set';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';
    SELECT val::int INTO __api_key_id FROM _ak_test_data WHERE key = 'key1_id';

    -- Unassign the system_admin perm_set
    PERFORM auth.unassign_api_key_permissions(
        'ak_test', __admin_id, 'ak-test-unassign',
        __api_key_id,
        'system_admin',
        null,
        1
    );

    -- Verify permissions are gone
    SELECT count(*)
    FROM auth.get_api_key_permissions(__admin_id, 'ak-test-check-unassign', __api_key_id, 1)
    INTO __remaining;

    IF __remaining = 0 THEN
        RAISE NOTICE '  PASS: all permissions removed after unassign (remaining=%)', __remaining;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 remaining permissions, got %', __remaining;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: unassign_api_key_permissions removes individual permissions
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __remaining int;
BEGIN
    RAISE NOTICE 'TEST 14: unassign_api_key_permissions removes individual permissions';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';
    SELECT val::int INTO __api_key_id FROM _ak_test_data WHERE key = 'key2_id';

    -- Unassign individual permissions
    PERFORM auth.unassign_api_key_permissions(
        'ak_test', __admin_id, 'ak-test-unassign-indiv',
        __api_key_id,
        null,
        array['users.read_users', 'users.read_all_users'],
        1
    );

    -- Verify permissions are gone
    SELECT count(*)
    FROM auth.get_api_key_permissions(__admin_id, 'ak-test-check-unassign2', __api_key_id, 1)
    INTO __remaining;

    IF __remaining = 0 THEN
        RAISE NOTICE '  PASS: individual permissions removed (remaining=%)', __remaining;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 remaining permissions, got %', __remaining;
    END IF;
END $$;
