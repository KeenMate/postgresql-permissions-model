set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 19: create additional outbound keys for search tests
-- ============================================================================
DO $$
DECLARE
    __id int;
BEGIN
    RAISE NOTICE 'TEST 19: create additional outbound keys for search';

    -- key 3
    SELECT r.__api_key_id
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-s1',
        'Search Key Gamma', 'Gamma service key',
        'oaksvc_gamma',
        '\x1111'::bytea,
        'https://gamma.example.com'
    ) r INTO __id;
    PERFORM set_config('test.oak_key3_id', __id::text, false);

    -- key 4
    SELECT r.__api_key_id
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-s2',
        'Search Key Delta', 'Delta service key',
        'oaksvc_delta',
        '\x2222'::bytea,
        'https://delta.example.com'
    ) r INTO __id;
    PERFORM set_config('test.oak_key4_id', __id::text, false);

    -- key 5
    SELECT r.__api_key_id
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-s3',
        'Search Key Epsilon', 'Epsilon service key',
        'oaksvc_epsilon',
        '\x3333'::bytea
    ) r INTO __id;
    PERFORM set_config('test.oak_key5_id', __id::text, false);

    RAISE NOTICE '  PASS: created 3 additional outbound keys for search tests';
END $$;

-- ============================================================================
-- TEST 20: search_outbound_api_keys returns all outbound keys
-- ============================================================================
DO $$
DECLARE
    __total bigint;
BEGIN
    RAISE NOTICE 'TEST 20: search_outbound_api_keys returns all outbound keys';

    SELECT r.__total_items
    FROM auth.search_outbound_api_keys(1, 'oak-corr-search1', null, 1, 100) r
    LIMIT 1
    INTO __total;

    -- we have key1 (alpha) + key3 (gamma) + key4 (delta) + key5 (epsilon) = 4
    -- (key2 beta was deleted)
    IF __total >= 4 THEN
        RAISE NOTICE '  PASS: search returned total_items=% (expected >= 4)', __total;
    ELSE
        RAISE EXCEPTION '  FAIL: search returned total_items=% (expected >= 4)', __total;
    END IF;
END $$;

-- ============================================================================
-- TEST 21: search_outbound_api_keys filters by service_code
-- ============================================================================
DO $$
DECLARE
    __total bigint;
    __service text;
BEGIN
    RAISE NOTICE 'TEST 21: search_outbound_api_keys filters by service_code';

    SELECT r.__total_items, r.__service_code
    FROM auth.search_outbound_api_keys(1, 'oak-corr-search2', '{"service_code": "oaksvc_gamma"}'::jsonb, 1, 10) r
    LIMIT 1
    INTO __total, __service;

    IF __total = 1 AND __service = 'oaksvc_gamma' THEN
        RAISE NOTICE '  PASS: filtered by service_code (total=%, service=%)', __total, __service;
    ELSE
        RAISE EXCEPTION '  FAIL: filter mismatch (total=%, service=%)', __total, __service;
    END IF;
END $$;

-- ============================================================================
-- TEST 22: search_outbound_api_keys filters by search_text
-- ============================================================================
DO $$
DECLARE
    __total bigint;
    __title text;
BEGIN
    RAISE NOTICE 'TEST 22: search_outbound_api_keys filters by search_text';

    SELECT r.__total_items, r.__title
    FROM auth.search_outbound_api_keys(1, 'oak-corr-search3', '{"search_text": "delta"}'::jsonb, 1, 10) r
    LIMIT 1
    INTO __total, __title;

    IF __total >= 1 AND lower(__title) LIKE '%delta%' THEN
        RAISE NOTICE '  PASS: filtered by search_text (total=%, title=%)', __total, __title;
    ELSE
        RAISE EXCEPTION '  FAIL: text filter mismatch (total=%, title=%)', __total, __title;
    END IF;
END $$;

-- ============================================================================
-- TEST 23: search_outbound_api_keys pagination works
-- ============================================================================
DO $$
DECLARE
    __page1_count int;
    __page2_count int;
    __total bigint;
BEGIN
    RAISE NOTICE 'TEST 23: search_outbound_api_keys pagination works';

    -- page 1 with page_size=2
    SELECT count(*), max(r.__total_items)
    FROM auth.search_outbound_api_keys(1, 'oak-corr-page1', null, 1, 2) r
    INTO __page1_count, __total;

    -- page 2 with page_size=2
    SELECT count(*)
    FROM auth.search_outbound_api_keys(1, 'oak-corr-page2', null, 2, 2) r
    INTO __page2_count;

    IF __page1_count = 2 AND __page2_count >= 1 AND __total >= 4 THEN
        RAISE NOTICE '  PASS: pagination (page1=% rows, page2=% rows, total=%)', __page1_count, __page2_count, __total;
    ELSE
        RAISE EXCEPTION '  FAIL: pagination mismatch (page1=%, page2=%, total=%)', __page1_count, __page2_count, __total;
    END IF;
END $$;

-- ============================================================================
-- TEST 24: search_outbound_api_keys returns empty for no match
-- ============================================================================
DO $$
DECLARE
    __count int;
BEGIN
    RAISE NOTICE 'TEST 24: search_outbound_api_keys returns empty for no match';

    SELECT count(*)
    FROM auth.search_outbound_api_keys(1, 'oak-corr-empty', '{"service_code": "nonexistent_service"}'::jsonb, 1, 10) r
    INTO __count;

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: no results for nonexistent service_code';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 results, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 25: service_code is stored in lowercase
-- ============================================================================
DO $$
DECLARE
    __id int;
    __db_service text;
BEGIN
    RAISE NOTICE 'TEST 25: service_code is stored in lowercase';

    SELECT r.__api_key_id
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-case',
        'Case Test Key', 'Uppercase service code',
        'OAKSVC_UPPER',
        '\xFFFF'::bytea
    ) r
    INTO __id;

    SELECT ak.service_code
    FROM auth.api_key ak
    WHERE ak.api_key_id = __id
    INTO __db_service;

    IF __db_service = 'oaksvc_upper' THEN
        RAISE NOTICE '  PASS: service_code stored as lowercase (%)' , __db_service;
    ELSE
        RAISE EXCEPTION '  FAIL: service_code not lowercased (%)' , __db_service;
    END IF;
END $$;
