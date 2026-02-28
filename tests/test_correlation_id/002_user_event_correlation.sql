set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
