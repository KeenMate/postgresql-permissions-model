/*
 * Test: Search Functions
 * ======================
 *
 * Verifies that all search functions:
 * 1. Execute without errors (catches stale function references like unaccent_text)
 * 2. Return results with proper pagination (total_items, page/page_size)
 * 3. Filter by search text using normalize_text
 * 4. Return empty results for non-matching search text
 *
 * Covers:
 * - auth.search_api_keys
 * - auth.search_outbound_api_keys
 * - auth.search_users
 * - auth.search_user_groups
 * - auth.search_permissions
 * - auth.search_perm_sets
 * - auth.search_tenants
 * - public.search_journal
 * - auth.search_user_events
 *
 * Run with: ./exec-sql.sh -f tests/test_search_functions.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Search Functions Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test data for search
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __api_key_id integer;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create a test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test_search', 'test_search', 'normal', 'search_test_user', 'search_test_user', 'Search Test User', 'search_test@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Search Test User'
    RETURNING user_id INTO __test_user_id;

    -- Create an inbound API key for search testing
    INSERT INTO auth.api_key (created_by, updated_by, tenant_id, title, description, api_key, secret_hash, key_type)
    VALUES ('test_search', 'test_search', 1, 'Search Test API Key', 'API key for search tests', 'search_test_key_001', '\x1234', 'inbound')
    ON CONFLICT (api_key) DO NOTHING;

    -- Create an outbound API key for search testing
    INSERT INTO auth.api_key (created_by, updated_by, tenant_id, title, description, api_key, key_type, encrypted_secret, service_code, service_url)
    VALUES ('test_search', 'test_search', 1, 'Search Test Outbound Key', 'Outbound key for search tests', 'search_test_outbound_001', 'outbound', '\x5678', 'test_service', 'https://test.example.com')
    ON CONFLICT (api_key) DO NOTHING;

    -- Create a journal entry for search testing
    INSERT INTO public.journal (created_by, correlation_id, tenant_id, event_id, user_id, data_payload)
    SELECT 'test_search', 'search-test-corr', 1, ec.event_id, 1, '{"test": true}'::jsonb
    FROM const.event_code ec LIMIT 1;

    -- Create a user event for search testing
    INSERT INTO auth.user_event (created_by, correlation_id, event_type_code, requester_user_id, target_user_id)
    VALUES ('test_search', 'search-test-corr', 'user_logged_in', 1, __test_user_id);

    RAISE NOTICE 'SETUP: Test user_id=%, created API keys and journal entries', __test_user_id;
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: auth.search_api_keys executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 1: auth.search_api_keys executes without error';

    SELECT count(*) INTO __count FROM auth.search_api_keys(1, null, null);

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

    SELECT count(*) INTO __count_all FROM auth.search_api_keys(1, null, null);
    SELECT count(*) INTO __count_filtered FROM auth.search_api_keys(1, null, 'search test api');

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

    SELECT count(*) INTO __count FROM auth.search_api_keys(1, null, 'zzz_nonexistent_xyz_12345');

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: no results for non-matching text';
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 results, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: auth.search_outbound_api_keys executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 4: auth.search_outbound_api_keys executes without error';

    SELECT count(*) INTO __count FROM auth.search_outbound_api_keys(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_outbound_api_keys returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: auth.search_outbound_api_keys filters by service_code
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 5: auth.search_outbound_api_keys filters by service_code';

    SELECT count(*) INTO __count FROM auth.search_outbound_api_keys(1, null, _service_code := 'test_service');

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: found % outbound key(s) for service_code "test_service"', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 result, got %', __count;
    END IF;
END $$;

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

-- ============================================================================
-- TEST 12: public.search_journal executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 12: public.search_journal executes without error';

    SELECT count(*) INTO __count FROM public.search_journal(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_journal returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: auth.search_user_events executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 13: auth.search_user_events executes without error';

    SELECT count(*) INTO __count FROM auth.search_user_events(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_user_events returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 14: Pagination works (page_size limits results)
-- ============================================================================
DO $$
DECLARE
    __total bigint;
    __returned_count bigint;
BEGIN
    RAISE NOTICE 'TEST 14: Pagination limits results';

    SELECT count(*), max(r.__total_items)
    INTO __returned_count, __total
    FROM auth.search_permissions(1, null, null, _page_size := 2) r;

    IF __returned_count <= 2 AND __total > __returned_count THEN
        RAISE NOTICE '  PASS: page_size=2 returned % rows, total_items=%', __returned_count, __total;
    ELSIF __returned_count <= 2 THEN
        RAISE NOTICE '  PASS: page_size=2 returned % rows (total_items=%)', __returned_count, __total;
    ELSE
        RAISE EXCEPTION '  FAIL: page_size=2 should return at most 2 rows, got %', __returned_count;
    END IF;
END $$;

-- ============================================================================
-- CLEANUP
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_event WHERE created_by = 'test_search';
    DELETE FROM public.journal WHERE created_by = 'test_search';
    DELETE FROM auth.api_key WHERE created_by = 'test_search';
    DELETE FROM auth.user_info WHERE username = 'search_test_user';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Search Functions Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 14 tests passed:';
    RAISE NOTICE '  1. search_api_keys executes without error';
    RAISE NOTICE '  2. search_api_keys filters by search text';
    RAISE NOTICE '  3. search_api_keys returns empty for non-matching text';
    RAISE NOTICE '  4. search_outbound_api_keys executes without error';
    RAISE NOTICE '  5. search_outbound_api_keys filters by service_code';
    RAISE NOTICE '  6. search_users executes without error';
    RAISE NOTICE '  7. search_users filters by search text';
    RAISE NOTICE '  8. search_user_groups executes without error';
    RAISE NOTICE '  9. search_permissions executes without error';
    RAISE NOTICE '  10. search_perm_sets executes without error';
    RAISE NOTICE '  11. search_tenants executes without error';
    RAISE NOTICE '  12. search_journal executes without error';
    RAISE NOTICE '  13. search_user_events executes without error';
    RAISE NOTICE '  14. Pagination limits results';
    RAISE NOTICE '';
END $$;
