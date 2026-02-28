set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
