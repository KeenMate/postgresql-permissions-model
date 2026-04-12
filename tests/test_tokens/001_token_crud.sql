set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_token returns valid token_id, uid, and expires_at
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __expires_at timestamptz;
    __db_token auth.token;
BEGIN
    RAISE NOTICE 'TEST 1: create_token returns valid token_id, uid, and expires_at';

    SELECT ct.___token_id, ct.___token_uid, ct.___expires_at
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-01',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_001'
    ) ct
    INTO __token_id, __token_uid, __expires_at;

    IF __token_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_token returned NULL token_id';
    END IF;

    IF __token_uid IS NULL OR length(__token_uid) = 0 THEN
        RAISE EXCEPTION '  FAIL: create_token returned NULL or empty uid';
    END IF;

    IF __expires_at IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_token returned NULL expires_at';
    END IF;

    -- Verify the token exists in the database with correct state
    SELECT * FROM auth.token WHERE token_id = __token_id INTO __db_token;

    IF __db_token.token_state_code <> 'valid' THEN
        RAISE EXCEPTION '  FAIL: expected state=valid, got %', __db_token.token_state_code;
    END IF;

    IF __db_token.token_type_code <> 'password_reset' THEN
        RAISE EXCEPTION '  FAIL: expected type=password_reset, got %', __db_token.token_type_code;
    END IF;

    IF __db_token.token_channel_code <> 'email' THEN
        RAISE EXCEPTION '  FAIL: expected channel=email, got %', __db_token.token_channel_code;
    END IF;

    IF __db_token.user_id <> __target_id THEN
        RAISE EXCEPTION '  FAIL: expected user_id=%, got %', __target_id, __db_token.user_id;
    END IF;

    -- Store token data for subsequent tests
    PERFORM set_config('test.token_id', __token_id::text, false);
    PERFORM set_config('test.token_uid', __token_uid, false);

    RAISE NOTICE '  PASS: token created (id=%, uid=%, expires_at=%, state=%, type=%, channel=%)',
        __token_id, __token_uid, __expires_at, __db_token.token_state_code,
        __db_token.token_type_code, __db_token.token_channel_code;
END $$;

-- ============================================================================
-- TEST 2: create_token journals event 15001
-- ============================================================================
DO $$
DECLARE
    __token_id bigint := current_setting('test.token_id')::bigint;
    __journal_keys jsonb;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 2: create_token journals event 15001';

    SELECT j.keys, j.data_payload
    FROM public.journal j
    WHERE j.event_id = 15001
      AND j.created_by = 'tok_test'
      AND j.correlation_id = 'tok-test-01'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys, __journal_payload;

    IF __journal_keys IS NULL THEN
        RAISE EXCEPTION '  FAIL: No journal entry found for event 15001';
    END IF;

    IF (__journal_keys->>'token')::bigint <> __token_id THEN
        RAISE EXCEPTION '  FAIL: journal token key mismatch (expected=%, got=%)',
            __token_id, __journal_keys->>'token';
    END IF;

    IF __journal_payload->>'token_type' <> 'password_reset' THEN
        RAISE EXCEPTION '  FAIL: journal payload token_type mismatch (got=%)', __journal_payload->>'token_type';
    END IF;

    RAISE NOTICE '  PASS: journal entry found (keys=%, payload=%)', __journal_keys, __journal_payload;
END $$;

-- ============================================================================
-- TEST 3: validate_token succeeds for valid token
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_uid text := current_setting('test.token_uid');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 3: validate_token succeeds for valid token';

    SELECT vt.___token_id, vt.___token_uid, vt.___token_state_code, vt.___user_id
    FROM auth.validate_token(
        'tok_test', __admin_id, 'tok-test-03',
        __target_id, __token_uid, 'test_token_value_001',
        'password_reset', '{"ip": "127.0.0.1"}'::jsonb, false
    ) vt
    INTO __result;

    IF __result.___token_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: validate_token returned NULL token_id';
    END IF;

    IF __result.___token_state_code <> 'valid' THEN
        RAISE EXCEPTION '  FAIL: expected state=valid, got %', __result.___token_state_code;
    END IF;

    IF __result.___user_id <> __target_id THEN
        RAISE EXCEPTION '  FAIL: expected user_id=%, got %', __target_id, __result.___user_id;
    END IF;

    RAISE NOTICE '  PASS: token validated (id=%, state=%, user_id=%)',
        __result.___token_id, __result.___token_state_code, __result.___user_id;
END $$;

-- ============================================================================
-- TEST 4: set_token_as_used marks token and returns correct state
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __token_uid text := current_setting('test.token_uid');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 4: set_token_as_used marks token and returns correct state';

    SELECT st.__token_id, st.__token_uid, st.__token_state_code, st.__used_at, st.__user_id
    FROM auth.set_token_as_used(
        'tok_test', __admin_id, 'tok-test-04',
        __token_uid, 'test_token_value_001', 'password_reset',
        '{"ip": "127.0.0.1"}'::jsonb
    ) st
    INTO __result;

    IF __result.__token_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: set_token_as_used returned NULL token_id';
    END IF;

    IF __result.__token_state_code <> 'used' THEN
        RAISE EXCEPTION '  FAIL: expected state=used, got %', __result.__token_state_code;
    END IF;

    IF __result.__used_at IS NULL THEN
        RAISE EXCEPTION '  FAIL: used_at should not be NULL';
    END IF;

    RAISE NOTICE '  PASS: token marked as used (id=%, state=%, used_at=%)',
        __result.__token_id, __result.__token_state_code, __result.__used_at;
END $$;

-- ============================================================================
-- TEST 5: validate_token fails for already-used token (error 52278)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_uid text := current_setting('test.token_uid');
    __caught boolean := false;
BEGIN
    RAISE NOTICE 'TEST 5: validate_token fails for already-used token';

    BEGIN
        PERFORM auth.validate_token(
            'tok_test', __admin_id, 'tok-test-05',
            __target_id, __token_uid, 'test_token_value_001',
            'password_reset', '{"ip": "127.0.0.1"}'::jsonb, false
        );
    EXCEPTION WHEN OTHERS THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE '  PASS: validate_token correctly raised error for used token';
    ELSE
        RAISE EXCEPTION '  FAIL: validate_token should have raised error for used token';
    END IF;
END $$;

-- ============================================================================
-- TEST 6: create_token with custom expiration sets correct expires_at
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __custom_expires timestamptz := now() + interval '7 days';
    __token_id bigint;
    __token_uid text;
    __expires_at timestamptz;
BEGIN
    RAISE NOTICE 'TEST 6: create_token with custom expiration';

    SELECT ct.___token_id, ct.___token_uid, ct.___expires_at
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-06',
        __target_id, 'tok_test_oid', null,
        'email_verification', 'email',
        'test_token_value_006',
        __custom_expires
    ) ct
    INTO __token_id, __token_uid, __expires_at;

    IF __token_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_token returned NULL token_id';
    END IF;

    -- The returned expires_at should match the custom value (within 1 second tolerance)
    IF abs(extract(epoch from __expires_at - __custom_expires)) > 1 THEN
        RAISE EXCEPTION '  FAIL: expires_at mismatch (expected=%, got=%)', __custom_expires, __expires_at;
    END IF;

    PERFORM set_config('test.token_uid_006', __token_uid, false);

    RAISE NOTICE '  PASS: custom expiration set (id=%, expires_at=%)', __token_id, __expires_at;
END $$;

-- ============================================================================
-- TEST 7: create_token with token_data stores jsonb payload
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __db_token_data jsonb;
BEGIN
    RAISE NOTICE 'TEST 7: create_token with token_data stores jsonb payload';

    SELECT ct.___token_id
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-07',
        __target_id, 'tok_test_oid', null,
        'email_verification', 'email',
        'test_token_value_007',
        null,
        '{"redirect_url": "https://example.com/verify", "extra": 42}'::jsonb
    ) ct
    INTO __token_id;

    SELECT token_data
    FROM auth.token
    WHERE token_id = __token_id
    INTO __db_token_data;

    IF __db_token_data IS NULL THEN
        RAISE EXCEPTION '  FAIL: token_data is NULL';
    END IF;

    IF __db_token_data->>'redirect_url' <> 'https://example.com/verify' THEN
        RAISE EXCEPTION '  FAIL: token_data redirect_url mismatch (got=%)', __db_token_data;
    END IF;

    IF (__db_token_data->>'extra')::int <> 42 THEN
        RAISE EXCEPTION '  FAIL: token_data extra mismatch (got=%)', __db_token_data;
    END IF;

    RAISE NOTICE '  PASS: token_data stored correctly (data=%)', __db_token_data;
END $$;

-- ============================================================================
-- TEST 8: create_token invalidates previous valid tokens of same type for same user
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id_1 bigint;
    __token_uid_1 text;
    __token_id_2 bigint;
    __state_1 text;
    __state_2 text;
BEGIN
    RAISE NOTICE 'TEST 8: create_token invalidates previous valid tokens of same type';

    -- Create first token
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-08a',
        __target_id, 'tok_test_oid', null,
        'invite', 'email',
        'test_token_value_008a'
    ) ct
    INTO __token_id_1, __token_uid_1;

    -- Verify first token is valid
    SELECT token_state_code FROM auth.token WHERE token_id = __token_id_1 INTO __state_1;
    IF __state_1 <> 'valid' THEN
        RAISE EXCEPTION '  FAIL: first token should be valid, got %', __state_1;
    END IF;

    -- Create second token for same user and same type
    SELECT ct.___token_id
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-08b',
        __target_id, 'tok_test_oid', null,
        'invite', 'email',
        'test_token_value_008b'
    ) ct
    INTO __token_id_2;

    -- First token should now be invalidated
    SELECT token_state_code FROM auth.token WHERE token_id = __token_id_1 INTO __state_1;
    SELECT token_state_code FROM auth.token WHERE token_id = __token_id_2 INTO __state_2;

    IF __state_1 <> 'invalid' THEN
        RAISE EXCEPTION '  FAIL: first token should be invalidated, got %', __state_1;
    END IF;

    IF __state_2 <> 'valid' THEN
        RAISE EXCEPTION '  FAIL: second token should be valid, got %', __state_2;
    END IF;

    RAISE NOTICE '  PASS: previous token invalidated (token1=%, token2=%)', __state_1, __state_2;
END $$;

-- ============================================================================
-- TEST 9: validate_token fails for non-existent token (error 52277)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __caught boolean := false;
BEGIN
    RAISE NOTICE 'TEST 9: validate_token fails for non-existent token';

    BEGIN
        PERFORM auth.validate_token(
            'tok_test', __admin_id, 'tok-test-09',
            __target_id, 'nonexistent_uid', 'nonexistent_token',
            'password_reset', '{"ip": "127.0.0.1"}'::jsonb, false
        );
    EXCEPTION WHEN OTHERS THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE '  PASS: validate_token correctly raised error for non-existent token';
    ELSE
        RAISE EXCEPTION '  FAIL: validate_token should have raised error for non-existent token';
    END IF;
END $$;

-- ============================================================================
-- TEST 10: validate_token with _set_as_used=true marks token as used
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __result record;
    __db_state text;
BEGIN
    RAISE NOTICE 'TEST 10: validate_token with _set_as_used=true marks token as used';

    -- Create a fresh token
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-10a',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_010'
    ) ct
    INTO __token_id, __token_uid;

    -- Validate with set_as_used=true
    SELECT vt.___token_id, vt.___token_uid, vt.___token_state_code
    FROM auth.validate_token(
        'tok_test', __admin_id, 'tok-test-10b',
        __target_id, __token_uid, 'test_token_value_010',
        'password_reset', '{"ip": "127.0.0.1"}'::jsonb, true
    ) vt
    INTO __result;

    IF __result.___token_state_code <> 'used' THEN
        RAISE EXCEPTION '  FAIL: expected state=used from validate_token, got %', __result.___token_state_code;
    END IF;

    -- Verify in database
    SELECT token_state_code FROM auth.token WHERE token_id = __token_id INTO __db_state;

    IF __db_state <> 'used' THEN
        RAISE EXCEPTION '  FAIL: expected db state=used, got %', __db_state;
    END IF;

    RAISE NOTICE '  PASS: validate_token with set_as_used=true works (state=%)', __result.___token_state_code;
END $$;

-- ============================================================================
-- TEST 11: set_token_as_failed marks token with validation_failed state
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 11: set_token_as_failed marks token with validation_failed state';

    -- Create a fresh token
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-11a',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_011'
    ) ct
    INTO __token_id, __token_uid;

    -- Mark as failed
    SELECT st.__token_id, st.__token_state_code, st.__used_at
    FROM auth.set_token_as_failed(
        'tok_test', __admin_id, 'tok-test-11b',
        __token_uid, 'test_token_value_011', 'password_reset',
        '{"ip": "127.0.0.1", "reason": "wrong code"}'::jsonb
    ) st
    INTO __result;

    IF __result.__token_state_code <> 'validation_failed' THEN
        RAISE EXCEPTION '  FAIL: expected state=validation_failed, got %', __result.__token_state_code;
    END IF;

    IF __result.__used_at IS NULL THEN
        RAISE EXCEPTION '  FAIL: used_at should not be NULL after failure';
    END IF;

    RAISE NOTICE '  PASS: token marked as failed (id=%, state=%, used_at=%)',
        __result.__token_id, __result.__token_state_code, __result.__used_at;
END $$;

-- ============================================================================
-- TEST 12: expired token fails validation
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __caught boolean := false;
BEGIN
    RAISE NOTICE 'TEST 12: expired token fails validation';

    -- Create a token with expiration in the past
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-12a',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_012',
        now() + interval '1 hour'
    ) ct
    INTO __token_id, __token_uid;

    -- Manually set expires_at to the past to simulate expiration
    UPDATE auth.token
    SET expires_at = now() - interval '1 hour',
        token_state_code = 'expired',
        updated_by = 'tok_test'
    WHERE token_id = __token_id;

    -- Attempt to validate the expired token
    BEGIN
        PERFORM auth.validate_token(
            'tok_test', __admin_id, 'tok-test-12b',
            __target_id, __token_uid, 'test_token_value_012',
            'password_reset', '{"ip": "127.0.0.1"}'::jsonb, false
        );
    EXCEPTION WHEN OTHERS THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE '  PASS: validate_token correctly raised error for expired token';
    ELSE
        RAISE EXCEPTION '  FAIL: validate_token should have raised error for expired token';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: validate_token with wrong user raises error (52279)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __caught boolean := false;
BEGIN
    RAISE NOTICE 'TEST 13: validate_token with wrong user raises error';

    -- Create a token for target user
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-13a',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_013'
    ) ct
    INTO __token_id, __token_uid;

    -- Validate with a different user_id (admin_id instead of target_id)
    BEGIN
        PERFORM auth.validate_token(
            'tok_test', __admin_id, 'tok-test-13b',
            __admin_id, __token_uid, 'test_token_value_013',
            'password_reset', '{"ip": "127.0.0.1"}'::jsonb, false
        );
    EXCEPTION WHEN OTHERS THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE '  PASS: validate_token correctly raised error for wrong user';
    ELSE
        RAISE EXCEPTION '  FAIL: validate_token should have raised error for wrong user';
    END IF;
END $$;

-- ============================================================================
-- TEST 14: duplicate token value raises error (52276)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __caught boolean := false;
BEGIN
    RAISE NOTICE 'TEST 14: duplicate token value raises error';

    -- Create first token with a specific value and type
    SELECT ct.___token_id
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-14a',
        null, 'tok_test_oid_dup', null,
        'email_verification', 'email',
        'test_token_value_014_dup'
    ) ct
    INTO __token_id;

    -- Try to create another token with the same value and type (without a target user to skip invalidation)
    BEGIN
        PERFORM auth.create_token(
            'tok_test', __admin_id, 'tok-test-14b',
            null, 'tok_test_oid_dup2', null,
            'email_verification', 'email',
            'test_token_value_014_dup'
        );
    EXCEPTION WHEN OTHERS THEN
        __caught := true;
    END;

    IF __caught THEN
        RAISE NOTICE '  PASS: duplicate token value correctly raised error';
    ELSE
        RAISE EXCEPTION '  FAIL: duplicate token value should have raised error';
    END IF;
END $$;

-- ============================================================================
-- TEST 15: set_token_as_used_by_token works without providing uid
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'admin_id');
    __target_id bigint := (SELECT val FROM _tok_test_data WHERE key = 'target_id');
    __token_id bigint;
    __token_uid text;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 15: set_token_as_used_by_token works without providing uid';

    -- Create a fresh token
    SELECT ct.___token_id, ct.___token_uid
    FROM auth.create_token(
        'tok_test', __admin_id, 'tok-test-15a',
        __target_id, 'tok_test_oid', null,
        'password_reset', 'email',
        'test_token_value_015'
    ) ct
    INTO __token_id, __token_uid;

    -- Use set_token_as_used_by_token (only needs token value + type, no uid)
    SELECT st.__token_id, st.__token_state_code, st.__token_uid
    FROM auth.set_token_as_used_by_token(
        'tok_test', __admin_id, 'tok-test-15b',
        'test_token_value_015', 'password_reset',
        '{"ip": "127.0.0.1"}'::jsonb
    ) st
    INTO __result;

    IF __result.__token_state_code <> 'used' THEN
        RAISE EXCEPTION '  FAIL: expected state=used, got %', __result.__token_state_code;
    END IF;

    IF __result.__token_uid <> __token_uid THEN
        RAISE EXCEPTION '  FAIL: uid mismatch (expected=%, got=%)', __token_uid, __result.__token_uid;
    END IF;

    RAISE NOTICE '  PASS: set_token_as_used_by_token works (id=%, state=%, uid=%)',
        __result.__token_id, __result.__token_state_code, __result.__token_uid;
END $$;
