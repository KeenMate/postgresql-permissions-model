set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 17: ensure_user_from_provider raises error on user disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 17: ensure_user_from_provider raises error 33003 on user disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_info SET is_active = false WHERE user_id = __aad_user_id;

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-disabled', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33003' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33003 (user disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33003, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_active = true WHERE user_id = __aad_user_id;
END $$;

-- ============================================================================
-- TEST 18: ensure_user_from_provider raises error on login disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 18: ensure_user_from_provider raises error 33005 on login disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_info SET can_login = false WHERE user_id = __aad_user_id;

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-canlogin', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33005' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33005 (login disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33005, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET can_login = true WHERE user_id = __aad_user_id;
END $$;

-- ============================================================================
-- TEST 19: ensure_user_from_provider raises error on identity disabled
-- ============================================================================
DO $$
DECLARE
    __aad_user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 19: ensure_user_from_provider raises error 33008 on identity disabled';

    __aad_user_id := current_setting('test.aad_user_id')::bigint;
    UPDATE auth.user_identity SET is_active = false WHERE user_id = __aad_user_id AND provider_code = 'aad';

    BEGIN
        PERFORM auth.ensure_user_from_provider('reg_test', 1, 'fail-provider-identity', 'aad', 'regtest_aad_uid_1', 'regtest_aad_oid_1',
            'regtest_aad_user', 'RegTest AAD User', 'regtest_aad@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33008' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33008 (identity disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33008, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_identity SET is_active = true WHERE user_id = __aad_user_id AND provider_code = 'aad';
END $$;
