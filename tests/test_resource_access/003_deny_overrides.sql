set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: User deny overrides group grant
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 1: User deny overrides group grant';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read to editors group on document 700
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-deny-1a', 'document', 700,
        _user_group_id := __group_id_1, _access_flags := array['read']);

    -- Verify user_2 (member of editors) can read
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-1b', 'document', 700, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE EXCEPTION '  FAIL: User should have group read access before deny';
    END IF;

    -- Deny read for user_2 specifically
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-corr-deny-1c', 'document', 700,
        __user_id_2, _access_flags := array['read']);

    -- Verify deny overrides group grant
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-1d', 'document', 700, 'read', 1, false)
    INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: User deny overrides group grant';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false after deny, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Deny only affects the denied flag, not others
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __result_read boolean;
    __result_write boolean;
BEGIN
    RAISE NOTICE 'TEST 2: Deny only affects the denied flag';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Grant read+write to editors group on document 710
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-deny-2a', 'document', 710,
        _user_group_id := __group_id_1, _access_flags := array['read', 'write']);

    -- Deny only read for user_2
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-corr-deny-2b', 'document', 710,
        __user_id_2, _access_flags := array['read']);

    -- Check: read should be denied, write should still be allowed
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-2c', 'document', 710, 'read', 1, false)
    INTO __result_read;

    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-2d', 'document', 710, 'write', 1, false)
    INTO __result_write;

    IF __result_read = false AND __result_write = true THEN
        RAISE NOTICE '  PASS: read denied (%), write allowed (%)', __result_read, __result_write;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected read=false, write=true, got read=%, write=%', __result_read, __result_write;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Revoking deny restores access
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __group_id_1 integer;
    __result boolean;
    __deleted bigint;
BEGIN
    RAISE NOTICE 'TEST 3: Revoking deny restores group access';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Document 700 has: group grant (read) + user deny (read) from TEST 1
    -- Verify currently denied
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-3a', 'document', 700, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE EXCEPTION '  FAIL: Should be denied before revoke';
    END IF;

    -- Revoke the deny (removes the deny row)
    SELECT auth.revoke_resource_access('test', __user_id_1, 'test-corr-deny-3b', 'document', 700,
        _target_user_id := __user_id_2, _access_flags := array['read'])
    INTO __deleted;

    -- Now group grant should take effect again
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-3c', 'document', 700, 'read', 1, false)
    INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: Revoking deny restores group access (deleted=%, result=%)', __deleted, __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true after deny revoke, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Grant flips deny to grant
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __result boolean;
    __is_deny boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Granting after deny flips is_deny to false';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Set up a deny
    PERFORM auth.deny_resource_access('test', __user_id_1, 'test-corr-deny-4a', 'document', 720,
        __user_id_2, _access_flags := array['read']);

    -- Verify denied
    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-4b', 'document', 720, 'read', 1, false)
    INTO __result;
    IF __result = true THEN
        RAISE EXCEPTION '  FAIL: Should be denied initially';
    END IF;

    -- Now grant (should flip is_deny to false)
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-deny-4c', 'document', 720,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    -- Verify the row was flipped, not duplicated
    SELECT ra.is_deny FROM auth.resource_access ra
    WHERE ra.resource_type = 'document' AND ra.resource_id = 720
      AND ra.user_id = __user_id_2 AND ra.access_flag = 'read'
    INTO __is_deny;

    SELECT auth.has_resource_access(__user_id_2, 'test-corr-deny-4d', 'document', 720, 'read', 1, false)
    INTO __result;

    IF __result = true AND __is_deny = false THEN
        RAISE NOTICE '  PASS: Grant flipped deny to grant (is_deny=%, access=%)', __is_deny, __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected is_deny=false, access=true, got is_deny=%, access=%', __is_deny, __result;
    END IF;
END $$;
