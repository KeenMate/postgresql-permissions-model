/*
 * Automated Tests: Correlation ID Support
 * ========================================
 *
 * Tests for v2.3.0 correlation ID feature:
 * - Correlation ID flows from auth.* functions to public.journal
 * - Correlation ID flows from auth.* functions to auth.user_event
 * - search_journal filters by correlation_id
 * - search_user_events filters by correlation_id
 *
 * Run with: ./exec-sql.sh -f tests/test_correlation_id.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Correlation ID Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __system_user_id bigint := 1;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email, is_active)
    VALUES ('corr_test', 'corr_test', 'normal', 'corr_test_user', 'corr_test_user', 'Correlation Test User', 'corr_test@test.com', true)
    ON CONFLICT (username) DO UPDATE SET display_name = 'Correlation Test User'
    RETURNING user_id INTO __test_user_id;

    -- Store test user id for subsequent tests
    PERFORM set_config('test.corr_user_id', __test_user_id::text, false);

    RAISE NOTICE 'SETUP: Test user_id=%', __test_user_id;
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: Correlation ID flows to public.journal via create_journal_message
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := 1;
    __corr_id text := 'corr-test-journal-' || gen_random_uuid()::text;
    __found_corr_id text;
BEGIN
    RAISE NOTICE 'TEST 1: Correlation ID flows to public.journal';

    -- Insert journal entry with correlation_id
    PERFORM create_journal_message_for_entity('corr_test', __user_id, __corr_id, 10001, 'user', 1::bigint,
        jsonb_build_object('username', 'corr_test_user'));

    -- Verify it was stored
    SELECT j.correlation_id INTO __found_corr_id
    FROM public.journal j
    WHERE j.correlation_id = __corr_id
    LIMIT 1;

    IF __found_corr_id = __corr_id THEN
        RAISE NOTICE '  PASS: Correlation ID "%" found in journal', __corr_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Correlation ID "%" not found in journal', __corr_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Correlation ID flows to auth.user_event via create_user_event
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := 1;
    __target_user_id bigint;
    __corr_id text := 'corr-test-event-' || gen_random_uuid()::text;
    __found_corr_id text;
BEGIN
    RAISE NOTICE 'TEST 2: Correlation ID flows to auth.user_event';

    __target_user_id := current_setting('test.corr_user_id')::bigint;

    -- Insert user event with correlation_id
    PERFORM unsecure.create_user_event('corr_test', __user_id, __corr_id, 'login',
        __target_user_id);

    -- Verify it was stored
    SELECT ue.correlation_id INTO __found_corr_id
    FROM auth.user_event ue
    WHERE ue.correlation_id = __corr_id
    LIMIT 1;

    IF __found_corr_id = __corr_id THEN
        RAISE NOTICE '  PASS: Correlation ID "%" found in user_event', __corr_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Correlation ID "%" not found in user_event', __corr_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: search_journal filters by correlation_id
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := 1;
    __corr_id text := 'corr-test-search-j-' || gen_random_uuid()::text;
    __result_count bigint;
    __result_corr_id text;
BEGIN
    RAISE NOTICE 'TEST 3: search_journal filters by correlation_id';

    -- Insert two journal entries: one with our correlation_id, one without
    PERFORM create_journal_message_for_entity('corr_test', __user_id, __corr_id, 10001, 'user', 1::bigint,
        jsonb_build_object('username', 'corr_test_user'));
    PERFORM create_journal_message_for_entity('corr_test', __user_id, null, 10002, 'user', 1::bigint,
        jsonb_build_object('username', 'corr_test_user'));

    -- Search with correlation_id filter
    SELECT sj.__total_items, sj.__correlation_id
    INTO __result_count, __result_corr_id
    FROM public.search_journal(__user_id, __corr_id) sj
    LIMIT 1;

    IF __result_count >= 1 AND __result_corr_id = __corr_id THEN
        RAISE NOTICE '  PASS: search_journal returned % result(s) matching correlation_id "%"', __result_count, __corr_id;
    ELSE
        RAISE EXCEPTION '  FAIL: search_journal returned count=%, corr_id=% (expected count>=1, corr_id=%)',
            __result_count, __result_corr_id, __corr_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: search_user_events filters by correlation_id
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := 1;
    __target_user_id bigint;
    __corr_id text := 'corr-test-search-ue-' || gen_random_uuid()::text;
    __result_count bigint;
    __result_corr_id text;
BEGIN
    RAISE NOTICE 'TEST 4: search_user_events filters by correlation_id';

    __target_user_id := current_setting('test.corr_user_id')::bigint;

    -- Insert user event with correlation_id
    PERFORM unsecure.create_user_event('corr_test', __user_id, __corr_id, 'login',
        __target_user_id);

    -- Search with correlation_id filter
    SELECT sue.__total_items, sue.__correlation_id
    INTO __result_count, __result_corr_id
    FROM auth.search_user_events(__user_id, __corr_id) sue
    LIMIT 1;

    IF __result_count >= 1 AND __result_corr_id = __corr_id THEN
        RAISE NOTICE '  PASS: search_user_events returned % result(s) matching correlation_id "%"', __result_count, __corr_id;
    ELSE
        RAISE EXCEPTION '  FAIL: search_user_events returned count=%, corr_id=% (expected count>=1, corr_id=%)',
            __result_count, __result_corr_id, __corr_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Null correlation_id is valid (backwards compatibility)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := 1;
    __journal_count bigint;
BEGIN
    RAISE NOTICE 'TEST 5: Null correlation_id is valid (backwards compatibility)';

    -- Insert journal entry with null correlation_id
    PERFORM create_journal_message_for_entity('corr_test', __user_id, null, 10001, 'user', 1::bigint,
        jsonb_build_object('username', 'corr_null_test'));

    SELECT count(*) INTO __journal_count
    FROM public.journal j
    WHERE j.created_by = 'corr_test'
      AND j.correlation_id IS NULL
      AND j.data_payload->>'username' = 'corr_null_test';

    IF __journal_count >= 1 THEN
        RAISE NOTICE '  PASS: Journal entry created with null correlation_id';
    ELSE
        RAISE EXCEPTION '  FAIL: Journal entry with null correlation_id not found';
    END IF;
END $$;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_event WHERE created_by = 'corr_test';
    DELETE FROM public.journal WHERE created_by = 'corr_test';
    DELETE FROM auth.user_info WHERE username = 'corr_test_user';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Correlation ID Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 5 tests passed:';
    RAISE NOTICE '  1. Correlation ID flows to public.journal';
    RAISE NOTICE '  2. Correlation ID flows to auth.user_event';
    RAISE NOTICE '  3. search_journal filters by correlation_id';
    RAISE NOTICE '  4. search_user_events filters by correlation_id';
    RAISE NOTICE '  5. Null correlation_id backwards compatibility';
    RAISE NOTICE '';
END $$;
