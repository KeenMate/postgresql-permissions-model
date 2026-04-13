set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: auth.create_user_event stores an event in auth.user_event
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-create-' || gen_random_uuid()::text;
    __event_id bigint;
    __found_event_type text;
    __found_corr_id text;
BEGIN
    RAISE NOTICE 'TEST 1: auth.create_user_event creates an audit event';

    -- Create an event
    SELECT ___user_event_id INTO __event_id
    FROM auth.create_user_event(
        'audit_test',
        __system_user_id,
        __corr_id,
        'user_login',
        __test_user_id,
        '{"ip": "127.0.0.1"}'::jsonb,
        '{"source": "test"}'::jsonb
    );

    IF __event_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_user_event returned null event id';
    END IF;

    -- Verify event is stored
    SELECT ue.event_type_code, ue.correlation_id
    INTO __found_event_type, __found_corr_id
    FROM auth.user_event ue
    WHERE ue.user_event_id = __event_id;

    IF __found_event_type = 'user_login' AND __found_corr_id = __corr_id THEN
        RAISE NOTICE '  PASS: Event id=% stored with type=% and correlation_id=%', __event_id, __found_event_type, __found_corr_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Event not found or wrong data. type=%, corr=%', __found_event_type, __found_corr_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: auth.create_user_event stores request_context and event_data
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-data-' || gen_random_uuid()::text;
    __event_id bigint;
    __found_request_context jsonb;
    __found_event_data jsonb;
BEGIN
    RAISE NOTICE 'TEST 2: auth.create_user_event stores request_context and event_data';

    SELECT ___user_event_id INTO __event_id
    FROM auth.create_user_event(
        'audit_test',
        __system_user_id,
        __corr_id,
        'user_login',
        __test_user_id,
        '{"ip": "10.0.0.1", "user_agent": "TestAgent"}'::jsonb,
        '{"detail": "password_auth"}'::jsonb
    );

    SELECT ue.request_context, ue.event_data
    INTO __found_request_context, __found_event_data
    FROM auth.user_event ue
    WHERE ue.user_event_id = __event_id;

    IF __found_request_context ->> 'ip' = '10.0.0.1'
       AND __found_event_data ->> 'detail' = 'password_auth' THEN
        RAISE NOTICE '  PASS: request_context and event_data stored correctly';
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%, event_data=%', __found_request_context, __found_event_data;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: auth.get_user_audit_trail returns events for a target user
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-trail-' || gen_random_uuid()::text;
    __trail_count bigint;
    __total bigint;
BEGIN
    RAISE NOTICE 'TEST 3: auth.get_user_audit_trail returns events for a target user';

    -- Create a few events for the test user
    PERFORM auth.create_user_event('audit_test', __system_user_id, __corr_id, 'user_login', __test_user_id);
    PERFORM auth.create_user_event('audit_test', __system_user_id, __corr_id, 'user_login', __test_user_id);

    -- Query the audit trail filtering by target_user_id
    SELECT count(*), max(__total_items)
    INTO __trail_count, __total
    FROM auth.get_user_audit_trail(
        __system_user_id,
        __corr_id,
        jsonb_build_object('target_user_id', __test_user_id),
        1, 50
    );

    IF __trail_count > 0 THEN
        RAISE NOTICE '  PASS: Audit trail returned % rows (total_items=%)', __trail_count, __total;
    ELSE
        RAISE EXCEPTION '  FAIL: Audit trail returned 0 rows for test user';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: auth.get_security_events returns security-related events
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-sec-' || gen_random_uuid()::text;
    __sec_count bigint;
BEGIN
    RAISE NOTICE 'TEST 4: auth.get_security_events returns security-related events';

    -- Create a security-relevant event (user_login_failed is one of the filtered types)
    PERFORM auth.create_user_event('audit_test', __system_user_id, __corr_id, 'user_login_failed', __test_user_id,
        '{"ip": "192.168.1.1"}'::jsonb);

    -- Query security events
    SELECT count(*)
    INTO __sec_count
    FROM auth.get_security_events(
        __system_user_id,
        __corr_id,
        null,
        1, 50
    );

    IF __sec_count > 0 THEN
        RAISE NOTICE '  PASS: Security events returned % rows', __sec_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Security events returned 0 rows (expected at least the user_login_failed event)';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: auth.search_user_events filters by event_type_code
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-search-' || gen_random_uuid()::text;
    __result_count bigint;
BEGIN
    RAISE NOTICE 'TEST 5: auth.search_user_events filters by event_type_code';

    -- Create events with different types
    PERFORM auth.create_user_event('audit_test', __system_user_id, __corr_id, 'user_login', __test_user_id);
    PERFORM auth.create_user_event('audit_test', __system_user_id, __corr_id, 'user_locked', __test_user_id);

    -- Search for only user_locked events with this correlation_id
    SELECT count(*)
    INTO __result_count
    FROM auth.search_user_events(
        __system_user_id,
        __corr_id,
        jsonb_build_object('event_type_code', 'user_locked', 'correlation_id', __corr_id),
        1, 50
    );

    IF __result_count = 1 THEN
        RAISE NOTICE '  PASS: search_user_events returned exactly 1 user_locked event';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 user_locked event, got %', __result_count;
    END IF;
END $$;
