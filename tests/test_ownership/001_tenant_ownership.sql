set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_owner assigns tenant owner (user_group_id = NULL)
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_own.admin_user_id')::bigint;
    __test_user_id bigint := current_setting('test_own.test_user_id')::bigint;
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 1: create_owner assigns tenant owner';

    SELECT o.__owner_id
    FROM auth.create_owner('test_own', __admin_user_id, 'own-corr-1', __test_user_id, null, __tenant_id) o
    INTO __owner_id;

    IF __owner_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_owner returned NULL owner_id';
    END IF;

    RAISE NOTICE '  PASS: tenant owner created (owner_id=%)', __owner_id;
END $$;

-- ============================================================================
-- TEST 2: is_owner returns true for assigned tenant owner
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_own.test_user_id')::bigint;
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 2: is_owner returns true for assigned tenant owner';

    SELECT auth.is_owner(__test_user_id, 'own-corr-2', null, __tenant_id) INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: is_owner returned true for tenant owner';
    ELSE
        RAISE EXCEPTION '  FAIL: is_owner returned false, expected true';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: has_owner returns true for tenant with owner
-- ============================================================================
DO $$
DECLARE
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 3: has_owner returns true for tenant with owner';

    SELECT auth.has_owner(null, __tenant_id) INTO __result;

    IF __result = true THEN
        RAISE NOTICE '  PASS: has_owner returned true';
    ELSE
        RAISE EXCEPTION '  FAIL: has_owner returned false, expected true';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: owner row exists in auth.owner with correct data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_own.test_user_id')::bigint;
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __db_user_id bigint;
    __db_tenant_id integer;
    __db_group_id integer;
BEGIN
    RAISE NOTICE 'TEST 4: owner row exists in auth.owner with correct data';

    SELECT user_id, tenant_id, user_group_id
    FROM auth.owner
    WHERE user_id = __test_user_id AND tenant_id = __tenant_id AND user_group_id IS NULL
    INTO __db_user_id, __db_tenant_id, __db_group_id;

    IF __db_user_id = __test_user_id AND __db_tenant_id = __tenant_id AND __db_group_id IS NULL THEN
        RAISE NOTICE '  PASS: owner row verified (user_id=%, tenant_id=%, user_group_id=NULL)', __db_user_id, __db_tenant_id;
    ELSE
        RAISE EXCEPTION '  FAIL: owner row mismatch or missing';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: create_owner journals event 11010
-- ============================================================================
DO $$
DECLARE
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 5: create_owner journals event 11010';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 11010
      AND j.created_by = 'test_own'
      AND j.correlation_id = 'own-corr-1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NULL THEN
        RAISE EXCEPTION '  FAIL: No journal entry found for event 11010';
    END IF;

    IF __journal_payload->>'action' = 'owner_added' THEN
        RAISE NOTICE '  PASS: journal entry found with action=owner_added, payload=%', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal action mismatch, payload=%', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: delete_owner with NULL group_id removes tenant owner
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_own.admin_user_id')::bigint;
    __test_user_id bigint := current_setting('test_own.test_user_id')::bigint;
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __count integer;
BEGIN
    RAISE NOTICE 'TEST 6: delete_owner with NULL group_id removes tenant owner';

    PERFORM auth.delete_owner('test_own', __admin_user_id, 'own-corr-del-null', __test_user_id, null, __tenant_id);

    SELECT count(*) INTO __count
    FROM auth.owner
    WHERE user_id = __test_user_id AND tenant_id = __tenant_id AND user_group_id IS NULL;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: tenant owner removed via delete_owner';
    ELSE
        RAISE EXCEPTION '  FAIL: expected owner row to be deleted, count=%', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: is_owner returns false after owner removed
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_own.test_user_id')::bigint;
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 8: is_owner returns false after owner removed';

    SELECT auth.is_owner(__test_user_id, 'own-corr-3', null, __tenant_id) INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: is_owner returned false after removal';
    ELSE
        RAISE EXCEPTION '  FAIL: is_owner returned true, expected false';
    END IF;
END $$;

-- ============================================================================
-- TEST 9: has_owner returns false for tenant without owners
-- ============================================================================
DO $$
DECLARE
    __tenant_id integer := current_setting('test_own.tenant_id')::integer;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 9: has_owner returns false for tenant without owners';

    SELECT auth.has_owner(null, __tenant_id) INTO __result;

    IF __result = false THEN
        RAISE NOTICE '  PASS: has_owner returned false';
    ELSE
        RAISE EXCEPTION '  FAIL: has_owner returned true, expected false';
    END IF;
END $$;
