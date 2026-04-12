set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 15: search_api_keys returns created keys
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __key_a_id int;
    __key_b_id int;
    __key_c_id int;
    __total bigint;
    __first_title text;
BEGIN
    RAISE NOTICE 'TEST 15: search_api_keys returns created keys';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    -- Create 3 additional keys with distinct titles for search
    SELECT r.__api_key_id FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-search', 'AK Search Alpha', 'Alpha key', null, null, _tenant_id := 1
    ) r INTO __key_a_id;

    SELECT r.__api_key_id FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-search', 'AK Search Beta', 'Beta key', null, null, _tenant_id := 1
    ) r INTO __key_b_id;

    SELECT r.__api_key_id FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-search', 'AK Search Gamma', 'Gamma key', null, null, _tenant_id := 1
    ) r INTO __key_c_id;

    INSERT INTO _ak_test_data VALUES ('search_a_id', __key_a_id::text) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _ak_test_data VALUES ('search_b_id', __key_b_id::text) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _ak_test_data VALUES ('search_c_id', __key_c_id::text) ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;

    -- Search without filter should return at least 3 keys
    SELECT r.__total_items
    FROM auth.search_api_keys(__admin_id, 'ak-test-search-all', null, 1, 100, 1) r
    LIMIT 1
    INTO __total;

    IF __total >= 3 THEN
        RAISE NOTICE '  PASS: search_api_keys returned total_items=% (>= 3)', __total;
    ELSE
        RAISE EXCEPTION '  FAIL: search_api_keys total_items=% (expected >= 3)', __total;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: search_api_keys filters by search_text
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __total bigint;
    __first_title text;
BEGIN
    RAISE NOTICE 'TEST 16: search_api_keys filters by search_text';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    -- Search for "Alpha" - should find exactly 1
    SELECT r.__total_items, r.__title
    FROM auth.search_api_keys(
        __admin_id, 'ak-test-search-filter',
        '{"search_text": "Search Alpha"}'::jsonb,
        1, 100, 1
    ) r
    LIMIT 1
    INTO __total, __first_title;

    IF __total = 1 AND __first_title = 'AK Search Alpha' THEN
        RAISE NOTICE '  PASS: search filtered to 1 result (title=%)', __first_title;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 1 result with title "AK Search Alpha", got total=%, title=%', __total, __first_title;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: search_api_keys pagination works
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __page1_count int;
    __page2_count int;
    __total bigint;
BEGIN
    RAISE NOTICE 'TEST 17: search_api_keys pagination works';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    -- Search with "AK Search" to get our 3 test keys, page_size=2
    SELECT count(*), max(r.__total_items)
    FROM auth.search_api_keys(
        __admin_id, 'ak-test-page1',
        '{"search_text": "AK Search"}'::jsonb,
        1, 2, 1
    ) r
    INTO __page1_count, __total;

    SELECT count(*)
    FROM auth.search_api_keys(
        __admin_id, 'ak-test-page2',
        '{"search_text": "AK Search"}'::jsonb,
        2, 2, 1
    ) r
    INTO __page2_count;

    IF __total = 3 AND __page1_count = 2 AND __page2_count = 1 THEN
        RAISE NOTICE '  PASS: pagination works (total=%, page1=%, page2=%)', __total, __page1_count, __page2_count;
    ELSE
        RAISE EXCEPTION '  FAIL: pagination mismatch (total=%, page1=%, page2=%)', __total, __page1_count, __page2_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 18: search_api_keys returns 12 columns
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 18: search_api_keys returns 12 columns';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    SELECT r.__created_by, r.__created_at, r.__updated_by, r.__updated_at,
           r.__api_key_id, r.__tenant_id, r.__title, r.__description,
           r.__api_key, r.__expire_at, r.__notification_email, r.__total_items
    FROM auth.search_api_keys(__admin_id, 'ak-test-cols', null, 1, 1, 1) r
    LIMIT 1
    INTO __rec;

    IF __rec.__api_key_id IS NOT NULL AND __rec.__total_items IS NOT NULL THEN
        RAISE NOTICE '  PASS: all 12 columns accessible (api_key_id=%, title=%, total=%)',
            __rec.__api_key_id, __rec.__title, __rec.__total_items;
    ELSE
        RAISE EXCEPTION '  FAIL: could not read all 12 columns';
    END IF;
END $$;

-- ============================================================================
-- TEST 19: search_api_keys with no matches returns empty
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 19: search_api_keys with no matches returns empty';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    SELECT count(*)
    FROM auth.search_api_keys(
        __admin_id, 'ak-test-empty',
        '{"search_text": "zzz_nonexistent_key_zzz"}'::jsonb,
        1, 10, 1
    ) r
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: empty search returned 0 rows';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 rows, got %', __count;
    END IF;
END $$;
