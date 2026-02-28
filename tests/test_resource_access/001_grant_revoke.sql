set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Grant read flag to a user
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __ra_id bigint;
    __flag text;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 1: Grant read flag to a user';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read access to user_2 on document 100
    SELECT __resource_access_id, __access_flag
    FROM auth.grant_resource_access('test', __user_id_1, 'test-corr-1', 'document', 100,
        _target_user_id := __user_id_2, _access_flags := array['read'])
    INTO __ra_id, __flag;

    IF __ra_id IS NOT NULL AND __flag = 'read' THEN
        RAISE NOTICE '  PASS: Granted read to user_2 on document 100 (ra_id=%)', __ra_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected grant to return id and flag, got ra_id=%, flag=%', __ra_id, __flag;
    END IF;

    -- Verify row exists in resource_access
    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 100 AND user_id = __user_id_2
    INTO __count;

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Row exists in resource_access (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 row in resource_access, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Grant multiple flags at once
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 2: Grant multiple flags at once';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read, write, delete to user_2 on document 200
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-2', 'document', 200,
        _target_user_id := __user_id_2, _access_flags := array['read', 'write', 'delete']);

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 200 AND user_id = __user_id_2
    INTO __count;

    IF __count = 3 THEN
        RAISE NOTICE '  PASS: 3 flags granted to user (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 flags, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Grant flags to a group
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __group_id_1 integer;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 3: Grant flags to a group';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-3', 'document', 300,
        _user_group_id := __group_id_1, _access_flags := array['read', 'write']);

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 300 AND user_group_id = __group_id_1
    INTO __count;

    IF __count = 2 THEN
        RAISE NOTICE '  PASS: 2 flags granted to group (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 flags for group, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Revoke specific flag
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __deleted bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 4: Revoke specific flag';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Revoke 'delete' from user_2 on document 200 (was granted in TEST 2)
    SELECT auth.revoke_resource_access('test', __user_id_1, 'test-corr-4', 'document', 200,
        _target_user_id := __user_id_2, _access_flags := array['delete'])
    INTO __deleted;

    IF __deleted = 1 THEN
        RAISE NOTICE '  PASS: Revoked 1 flag (deleted=%)', __deleted;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 deleted, got %', __deleted;
    END IF;

    -- Verify remaining flags
    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 200 AND user_id = __user_id_2
    INTO __count;

    IF __count = 2 THEN
        RAISE NOTICE '  PASS: 2 flags remain after revoking 1 (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 remaining flags, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Revoke all flags (null access_flags)
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __deleted bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 5: Revoke all flags for a user on a resource';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Revoke all remaining flags from user_2 on document 200
    SELECT auth.revoke_resource_access('test', __user_id_1, 'test-corr-5', 'document', 200,
        _target_user_id := __user_id_2)
    INTO __deleted;

    IF __deleted = 2 THEN
        RAISE NOTICE '  PASS: Revoked all 2 remaining flags (deleted=%)', __deleted;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 deleted, got %', __deleted;
    END IF;

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 200 AND user_id = __user_id_2
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: No flags remain (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 remaining, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Revoke all resource access (bulk cleanup)
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __group_id_1 integer;
    __deleted bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 6: Revoke all resource access for a resource';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_1' INTO __group_id_1;

    -- Document 300 has group grants from TEST 3
    SELECT auth.revoke_all_resource_access('test', __user_id_1, 'test-corr-6', 'document', 300)
    INTO __deleted;

    IF __deleted = 2 THEN
        RAISE NOTICE '  PASS: Bulk revoked 2 grants (deleted=%)', __deleted;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 deleted, got %', __deleted;
    END IF;

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 300
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: No grants remain for document 300 (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: Grant idempotency (re-granting same flag)
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 7: Grant idempotency - re-granting same flag';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Grant read twice
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-7a', 'document', 400,
        _target_user_id := __user_id_2, _access_flags := array['read']);
    PERFORM auth.grant_resource_access('test', __user_id_1, 'test-corr-7b', 'document', 400,
        _target_user_id := __user_id_2, _access_flags := array['read']);

    SELECT count(*) FROM auth.resource_access
    WHERE resource_type = 'document' AND resource_id = 400 AND user_id = __user_id_2 AND access_flag = 'read'
    INTO __count;

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Only 1 row after double grant (count=%)', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 row, got %', __count;
    END IF;
END $$;
