set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 14: ensure_user_from_provider fires user_registered for new user
-- ============================================================================
DO $$
DECLARE
    __result record;
    __event_count int;
    __event_provider text;
    __event_uid text;
    __corr_id text := 'provider-reg-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 14: ensure_user_from_provider fires user_registered for new user';

    SELECT * INTO __result
    FROM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');

    SELECT count(*), (ue.event_data->>'provider'), (ue.event_data->>'provider_uid')
    INTO __event_count, __event_provider, __event_uid
    FROM auth.user_event ue
    WHERE event_type_code = 'user_registered'
      AND target_user_id = __result.__user_id
      AND correlation_id = __corr_id
    GROUP BY ue.event_data->>'provider', ue.event_data->>'provider_uid';

    IF __event_count = 1 AND __event_provider = 'aad' AND __event_uid = 'regtest_aad_uid_1' THEN
        RAISE NOTICE '  PASS: user_registered event with provider=aad, provider_uid=regtest_aad_uid_1';
    ELSE
        RAISE EXCEPTION '  FAIL: event_count=%, provider=%, uid=%', __event_count, __event_provider, __event_uid;
    END IF;

    PERFORM set_config('test.aad_user_id', __result.__user_id::text, false);
END $$;

-- ============================================================================
-- TEST 15: ensure_user_from_provider fires user_logged_in for new user
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __event_count int;
BEGIN
    RAISE NOTICE 'TEST 15: ensure_user_from_provider fires user_logged_in for new user';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;

    -- The new user path also fires user_logged_in (registration is also a login)
    SELECT count(*) INTO __event_count
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id
      AND event_data->>'provider' = 'aad';

    IF __event_count >= 1 THEN
        RAISE NOTICE '  PASS: user_logged_in event also fired for new provider user';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected user_logged_in event for new user, found %', __event_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: ensure_user_from_provider fires user_logged_in for returning user
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __event_count_before int;
    __event_count_after int;
    __corr_id text := 'provider-login-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 16: ensure_user_from_provider fires user_logged_in for returning user';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;

    SELECT count(*) INTO __event_count_before
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id;

    -- Login again as existing user
    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');

    SELECT count(*) INTO __event_count_after
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND target_user_id = __aad_user_id;

    IF __event_count_after > __event_count_before THEN
        RAISE NOTICE '  PASS: user_logged_in count increased (% -> %)', __event_count_before, __event_count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: user_logged_in count did not increase (% -> %)', __event_count_before, __event_count_after;
    END IF;
END $$;
