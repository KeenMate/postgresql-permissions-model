set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 16: create_owner assigns tenant owner
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_tenant.admin_id')::bigint;
    __target_user_id bigint := current_setting('test_tenant.target_user_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 16: create_owner assigns tenant owner';

    SELECT co.__owner_id
    FROM auth.create_owner('tenant_test', 1, 'tenant-test-owner', __target_user_id, null, __tenant_id) co
    INTO __owner_id;

    IF __owner_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: owner created (owner_id=%)', __owner_id;
    ELSE
        RAISE EXCEPTION '  FAIL: create_owner returned NULL';
    END IF;

    PERFORM set_config('test_tenant.owner_id', __owner_id::text, false);
END $$;

-- ============================================================================
-- TEST 17: owner row exists in auth.owner
-- ============================================================================
DO $$
DECLARE
    __owner_id bigint := current_setting('test_tenant.owner_id')::bigint;
    __target_user_id bigint := current_setting('test_tenant.target_user_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __db_user_id bigint;
    __db_tenant_id int;
BEGIN
    RAISE NOTICE 'TEST 17: owner row exists in auth.owner';

    SELECT user_id, tenant_id
    FROM auth.owner
    WHERE owner_id = __owner_id
    INTO __db_user_id, __db_tenant_id;

    IF __db_user_id = __target_user_id AND __db_tenant_id = __tenant_id THEN
        RAISE NOTICE '  PASS: owner row verified (user_id=%, tenant_id=%)', __db_user_id, __db_tenant_id;
    ELSE
        RAISE EXCEPTION '  FAIL: owner row mismatch (user_id=%, tenant_id=%)', __db_user_id, __db_tenant_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 18: is_owner returns true for the assigned owner
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint := current_setting('test_tenant.target_user_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 18: is_owner returns true for the assigned owner';

    SELECT auth.is_owner(__target_user_id, null, null, __tenant_id) INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: is_owner returned true';
    ELSE
        RAISE EXCEPTION '  FAIL: is_owner returned % (expected true)', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 19: is_owner returns false for a non-owner
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_tenant.admin_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 19: is_owner returns false for a non-owner';

    SELECT auth.is_owner(__admin_id, null, null, __tenant_id) INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: is_owner returned false for non-owner';
    ELSE
        RAISE EXCEPTION '  FAIL: is_owner returned % (expected false)', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 20: create_owner journals event 11010
-- ============================================================================
DO $$
DECLARE
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __journal_keys jsonb;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 20: create_owner journals event 11010';

    SELECT j.keys, j.data_payload
    FROM public.journal j
    WHERE j.event_id = 11010
      AND j.created_by = 'tenant_test'
      AND j.correlation_id = 'tenant-test-owner'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys, __journal_payload;

    IF __journal_keys IS NULL THEN
        RAISE EXCEPTION '  FAIL: no journal entry found for event 11010';
    END IF;

    IF (__journal_keys->>'tenant')::int = __tenant_id
       AND __journal_payload->>'action' = 'owner_added' THEN
        RAISE NOTICE '  PASS: journal keys=%, payload=%', __journal_keys, __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (keys=%, payload=%)', __journal_keys, __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 21: delete_owner removes the ownership
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_tenant.admin_id')::bigint;
    __target_user_id bigint := current_setting('test_tenant.target_user_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __owner_id bigint := current_setting('test_tenant.owner_id')::bigint;
    __still_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 21: delete_owner removes the ownership';

    PERFORM auth.delete_owner('tenant_test', 1, 'tenant-test-del-owner', __target_user_id, null, __tenant_id);

    SELECT exists(SELECT 1 FROM auth.owner WHERE owner_id = __owner_id) INTO __still_exists;

    IF __still_exists = false THEN
        RAISE NOTICE '  PASS: owner deleted';
    ELSE
        RAISE EXCEPTION '  FAIL: owner still exists after delete_owner';
    END IF;
END $$;

-- ============================================================================
-- TEST 22: is_owner returns false after owner deleted
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint := current_setting('test_tenant.target_user_id')::bigint;
    __tenant_id int := current_setting('test_tenant.ug_tenant_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 22: is_owner returns false after owner deleted';

    SELECT auth.is_owner(__target_user_id, null, null, __tenant_id) INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: is_owner returned false after deletion';
    ELSE
        RAISE EXCEPTION '  FAIL: is_owner returned % (expected false after deletion)', __result;
    END IF;
END $$;
