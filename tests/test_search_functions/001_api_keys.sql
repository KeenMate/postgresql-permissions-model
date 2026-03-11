set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: auth.search_api_keys executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 1: auth.search_api_keys executes without error';

    SELECT count(*) INTO __count FROM auth.search_api_keys(1);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_api_keys returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: auth.search_api_keys filters by search text
-- ============================================================================
DO $$
DECLARE
    __count_all bigint;
    __count_filtered bigint;
BEGIN
    RAISE NOTICE 'TEST 2: auth.search_api_keys filters by search text';

    SELECT count(*) INTO __count_all FROM auth.search_api_keys(1);
    SELECT count(*) INTO __count_filtered FROM auth.search_api_keys(1, _search_criteria := '{"search_text": "search test api"}'::jsonb);

    IF __count_filtered >= 1 THEN
        RAISE NOTICE '  PASS: search found % result(s) matching "search test api" (% total)', __count_filtered, __count_all;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 result for "search test api", got %', __count_filtered;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: auth.search_api_keys returns empty for non-matching text
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 3: auth.search_api_keys returns empty for non-matching text';

    SELECT count(*) INTO __count FROM auth.search_api_keys(1, _search_criteria := '{"search_text": "zzz_nonexistent_xyz_12345"}'::jsonb);

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: no results for non-matching text';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 results, got %', __count;
    END IF;
END $$;
