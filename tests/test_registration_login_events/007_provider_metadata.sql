set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 20: ensure_user_from_provider passes request_context to events
-- ============================================================================
DO $$
DECLARE
    __ctx jsonb;
    __corr_id text := 'provider-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 20: ensure_user_from_provider passes request_context to events';

    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
        'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com',
        _request_context := '{"ip_address": "172.16.0.1", "user_agent": "ProviderAgent/3.0", "origin": "https://aad.test.com"}'::jsonb);

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND correlation_id = __corr_id;

    IF __ctx->>'ip_address' = '172.16.0.1' AND __ctx->>'user_agent' = 'ProviderAgent/3.0' AND __ctx->>'origin' = 'https://aad.test.com' THEN
        RAISE NOTICE '  PASS: request_context=%', __ctx;
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;

-- ============================================================================
-- TEST 21: NULL request_context stored as NULL (backwards compatibility)
-- ============================================================================
DO $$
DECLARE
    __ctx jsonb;
    __corr_id text := 'login-null-meta-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 21: NULL request_context stored as NULL (backwards compat)';

    PERFORM auth.get_user_by_email_for_authentication(1, __corr_id, 'regtest_user1@test.com');

    SELECT ue.request_context
    INTO __ctx
    FROM auth.user_event ue
    WHERE event_type_code = 'user_logged_in'
      AND correlation_id = __corr_id;

    IF __ctx IS NULL THEN
        RAISE NOTICE '  PASS: request_context is NULL when not provided';
    ELSE
        RAISE EXCEPTION '  FAIL: request_context=%', __ctx;
    END IF;
END $$;
