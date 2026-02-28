set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
