set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 6: auth.search_users executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 6: auth.search_users executes without error';

    SELECT count(*) INTO __count FROM auth.search_users(1, null, null);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: search_users returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 user, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: auth.search_users filters by search text
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 7: auth.search_users filters by search text';

    SELECT count(*) INTO __count FROM auth.search_users(1, null, 'search test user');

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: found % user(s) matching "search test user"', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 result, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: auth.search_user_groups executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 8: auth.search_user_groups executes without error';

    SELECT count(*) INTO __count FROM auth.search_user_groups(1, null, null);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: search_user_groups returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 group, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: auth.search_permissions executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 9: auth.search_permissions executes without error';

    SELECT count(*) INTO __count FROM auth.search_permissions(1, null, null);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: search_permissions returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 permission, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: auth.search_perm_sets executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 10: auth.search_perm_sets executes without error';

    SELECT count(*) INTO __count FROM auth.search_perm_sets(1, null, null);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: search_perm_sets returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 perm set, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: auth.search_tenants executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 11: auth.search_tenants executes without error';

    SELECT count(*) INTO __count FROM auth.search_tenants(1, null, null);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: search_tenants returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 tenant, got %', __count;
    END IF;
END $$;
