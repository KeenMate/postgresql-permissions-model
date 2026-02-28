set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 3: auth.register_user fires user_registered event
-- ============================================================================
DO $$
DECLARE
    __result record;
    __event_count int;
    __corr_id text := 'reg-test-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 3: auth.register_user fires user_registered event';

    -- Register a new user
    SELECT * INTO __result
    FROM auth.register_user('reg_test', 1, __corr_id, 'regtest_user1@test.com', '$hash$test123', 'RegTest User 1');

    -- Check user_registered event was created
    SELECT count(*) INTO __event_count
    FROM auth.user_event
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id;

    IF __event_count = 1 THEN
        RAISE NOTICE '  PASS: user_registered event created for user_id=%', __result.__user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 user_registered event, found %', __event_count;
    END IF;

    PERFORM set_config('test.reg_user1_id', __result.__user_id::text, false);
END $$;

-- ============================================================================
-- TEST 4: Password hash stored in correct column (not provider_oid)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __password_hash text;
    __provider_oid text;
BEGIN
    RAISE NOTICE 'TEST 4: Password hash stored in password_hash column (not provider_oid)';

    __user_id := current_setting('test.reg_user1_id')::bigint;

    SELECT uid.password_hash, uid.provider_oid
    INTO __password_hash, __provider_oid
    FROM auth.user_identity uid
    WHERE uid.user_id = __user_id
      AND uid.provider_code = 'email';

    IF __password_hash = '$hash$test123' AND __provider_oid = 'regtest_user1@test.com' THEN
        RAISE NOTICE '  PASS: password_hash="$hash$test123", provider_oid="%"', __provider_oid;
    ELSIF __password_hash IS NULL AND __provider_oid = '$hash$test123' THEN
        RAISE EXCEPTION '  FAIL: Hash in provider_oid instead of password_hash (the old bug)';
    ELSE
        RAISE EXCEPTION '  FAIL: password_hash=%, provider_oid=%', __password_hash, __provider_oid;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: register_user event contains request_context
-- ============================================================================
DO $$
DECLARE
    __result record;
    __ctx jsonb;
    __corr_id text := 'reg-test-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 5: register_user passes request_context to event';

    SELECT * INTO __result
    FROM auth.register_user('reg_test', 1, __corr_id, 'regtest_meta@test.com', '$hash$meta', 'RegTest Meta',
        _request_context := '{"ip_address": "192.168.1.1", "user_agent": "TestBrowser/1.0", "origin": "https://test.com"}'::jsonb);

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id;

    IF __ctx->>'ip_address' = '192.168.1.1' AND __ctx->>'user_agent' = 'TestBrowser/1.0' AND __ctx->>'origin' = 'https://test.com' THEN
        RAISE NOTICE '  PASS: request_context=%', __ctx;
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: register_user event contains email and provider in event_data
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __event_data jsonb;
BEGIN
    RAISE NOTICE 'TEST 6: register_user event_data contains email and provider';

    __user_id := current_setting('test.reg_user1_id')::bigint;

    SELECT ue.event_data INTO __event_data
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __user_id
    LIMIT 1;

    IF __event_data->>'provider' = 'email' AND __event_data->>'email' = 'regtest_user1@test.com' THEN
        RAISE NOTICE '  PASS: event_data=%', __event_data;
    ELSE
        RAISE EXCEPTION '  FAIL: event_data=%', __event_data;
    END IF;
END $$;
