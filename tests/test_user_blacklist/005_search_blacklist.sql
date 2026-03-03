set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 14: auth.search_blacklist returns paginated results
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 14: auth.search_blacklist returns paginated results';

    -- search all (we still have provider uid, provider oid entries + auto-blacklist entries)
    SELECT count(*) INTO __count
    FROM auth.search_blacklist(__admin_id, __corr_id);

    IF __count > 0 THEN
        RAISE NOTICE '  PASS: search_blacklist returned % entries', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 1 entry, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 15: auth.search_blacklist with search text
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __count int;
BEGIN
    RAISE NOTICE 'TEST 15: auth.search_blacklist with search text filter';

    SELECT count(*) INTO __count
    FROM auth.search_blacklist(__admin_id, __corr_id, _search_text := 'blacklisted-aad-uid');

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Search by provider_uid text found % entries', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 1 entry for provider_uid search, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: auth.search_blacklist with reason filter
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __count int;
BEGIN
    RAISE NOTICE 'TEST 16: auth.search_blacklist with reason filter';

    SELECT count(*) INTO __count
    FROM auth.search_blacklist(__admin_id, __corr_id, _reason := 'policy_violation');

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Search by reason found % entries', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 1 entry for reason filter, found %', __count;
    END IF;

    -- search for reason that has no entries
    SELECT count(*) INTO __count
    FROM auth.search_blacklist(__admin_id, __corr_id, _reason := 'nonexistent_reason');

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: Search by nonexistent reason returns empty';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 entries for nonexistent reason, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: auth.search_blacklist empty results
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __count int;
BEGIN
    RAISE NOTICE 'TEST 17: auth.search_blacklist with no matches';

    SELECT count(*) INTO __count
    FROM auth.search_blacklist(__admin_id, __corr_id, _search_text := 'zzz_nonexistent_zzz');

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: No matches returns empty set';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 entries for nonexistent search, found %', __count;
    END IF;
END $$;
