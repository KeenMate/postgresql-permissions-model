set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_outbound_api_key returns valid api_key_id and service_code
-- ============================================================================
DO $$
DECLARE
    __api_key_id int;
    __api_key text;
    __service_code text;
    __db_key_type text;
    __db_service_code text;
    __db_encrypted_secret bytea;
BEGIN
    RAISE NOTICE 'TEST 1: create_outbound_api_key returns valid api_key_id';

    SELECT r.__api_key_id, r.__api_key, r.__service_code
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-1',
        'Test Outbound Key 1', 'First outbound key',
        'oaksvc_alpha',
        '\xDEADBEEF'::bytea,
        'https://api.alpha.example.com',
        '{"header": "X-Api-Key"}'::jsonb,
        null,
        'notify@test.com'
    ) r
    INTO __api_key_id, __api_key, __service_code;

    IF __api_key_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_outbound_api_key returned NULL api_key_id';
    END IF;

    IF __service_code <> 'oaksvc_alpha' THEN
        RAISE EXCEPTION '  FAIL: service_code mismatch (expected=oaksvc_alpha, got=%)', __service_code;
    END IF;

    SELECT ak.key_type, ak.service_code, ak.encrypted_secret
    FROM auth.api_key ak
    WHERE ak.api_key_id = __api_key_id
    INTO __db_key_type, __db_service_code, __db_encrypted_secret;

    IF __db_key_type = 'outbound' AND __db_service_code = 'oaksvc_alpha' AND __db_encrypted_secret = '\xDEADBEEF'::bytea THEN
        RAISE NOTICE '  PASS: outbound key created (id=%, key=%, service=%)', __api_key_id, __api_key, __db_service_code;
    ELSE
        RAISE EXCEPTION '  FAIL: data mismatch (key_type=%, service=%, secret=%)', __db_key_type, __db_service_code, __db_encrypted_secret;
    END IF;

    -- store api_key_id for later tests
    PERFORM set_config('test.oak_key1_id', __api_key_id::text, false);
    PERFORM set_config('test.oak_key1_api_key', __api_key, false);
END $$;

-- ============================================================================
-- TEST 2: create_outbound_api_key journals event 14001 with key_type=outbound
-- ============================================================================
DO $$
DECLARE
    __api_key_id int;
    __journal_keys jsonb;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 2: create_outbound_api_key journals event 14001';

    __api_key_id := current_setting('test.oak_key1_id')::int;

    SELECT j.keys, j.data_payload
    FROM public.journal j
    WHERE j.event_id = 14001
      AND j.created_by = 'oak_test'
      AND j.correlation_id = 'oak-corr-1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys, __journal_payload;

    IF __journal_keys IS NULL THEN
        RAISE EXCEPTION '  FAIL: No journal entry found for event 14001';
    END IF;

    IF (__journal_keys->>'api_key')::int = __api_key_id
       AND __journal_payload->>'key_type' = 'outbound'
       AND __journal_payload->>'service_code' = 'oaksvc_alpha' THEN
        RAISE NOTICE '  PASS: journal keys=%, payload=%', __journal_keys, __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (keys=%, payload=%)', __journal_keys, __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: create_outbound_api_key rejects null service_code
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 3: create_outbound_api_key rejects null service_code';

    BEGIN
        PERFORM auth.create_outbound_api_key(
            'oak_test', 1, 'oak-corr-err1',
            'Bad Key', 'Missing service code',
            null,
            '\xABCD'::bytea
        );
        RAISE EXCEPTION '  FAIL: should have raised exception for null service_code';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Service code is required%' THEN
            RAISE NOTICE '  PASS: correctly rejected null service_code (%)' , SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 4: create_outbound_api_key rejects null encrypted_secret
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 4: create_outbound_api_key rejects null encrypted_secret';

    BEGIN
        PERFORM auth.create_outbound_api_key(
            'oak_test', 1, 'oak-corr-err2',
            'Bad Key', 'Missing secret',
            'oaksvc_nosecret',
            null
        );
        RAISE EXCEPTION '  FAIL: should have raised exception for null encrypted_secret';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Encrypted secret is required%' THEN
            RAISE NOTICE '  PASS: correctly rejected null encrypted_secret (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 5: get_outbound_api_key retrieves by service_code
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_title text;
    __result_service_url text;
    __result_extra jsonb;
BEGIN
    RAISE NOTICE 'TEST 5: get_outbound_api_key retrieves by service_code';

    SELECT r.__api_key_id, r.__title, r.__service_url, r.__extra_data
    FROM auth.get_outbound_api_key(1, 'oak-corr-get1', 'oaksvc_alpha') r
    INTO __result_id, __result_title, __result_service_url, __result_extra;

    IF __result_id = current_setting('test.oak_key1_id')::int
       AND __result_title = 'Test Outbound Key 1'
       AND __result_service_url = 'https://api.alpha.example.com'
       AND (__result_extra->>'header') = 'X-Api-Key' THEN
        RAISE NOTICE '  PASS: get by service_code returned correct data (id=%, title=%, url=%)', __result_id, __result_title, __result_service_url;
    ELSE
        RAISE EXCEPTION '  FAIL: data mismatch (id=%, title=%, url=%, extra=%)', __result_id, __result_title, __result_service_url, __result_extra;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: get_outbound_api_key_by_id retrieves by api_key_id
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_service_code text;
    __result_notification text;
BEGIN
    RAISE NOTICE 'TEST 6: get_outbound_api_key_by_id retrieves by id';

    SELECT r.__api_key_id, r.__service_code, r.__notification_email
    FROM auth.get_outbound_api_key_by_id(1, 'oak-corr-get2', current_setting('test.oak_key1_id')::int) r
    INTO __result_id, __result_service_code, __result_notification;

    IF __result_id IS NOT NULL
       AND __result_service_code = 'oaksvc_alpha'
       AND __result_notification = 'notify@test.com' THEN
        RAISE NOTICE '  PASS: get by id returned correct data (id=%, service=%, email=%)', __result_id, __result_service_code, __result_notification;
    ELSE
        RAISE EXCEPTION '  FAIL: data mismatch (id=%, service=%, email=%)', __result_id, __result_service_code, __result_notification;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: get_outbound_api_key_secret retrieves encrypted secret
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_secret bytea;
    __result_service text;
BEGIN
    RAISE NOTICE 'TEST 7: get_outbound_api_key_secret retrieves encrypted secret';

    SELECT r.__api_key_id, r.__encrypted_secret, r.__service_code
    FROM auth.get_outbound_api_key_secret('oak_test', 1, 'oak-corr-secret1', 'oaksvc_alpha') r
    INTO __result_id, __result_secret, __result_service;

    IF __result_id IS NOT NULL
       AND __result_secret = '\xDEADBEEF'::bytea
       AND __result_service = 'oaksvc_alpha' THEN
        RAISE NOTICE '  PASS: secret retrieved (id=%, service=%)', __result_id, __result_service;
    ELSE
        RAISE EXCEPTION '  FAIL: secret mismatch (id=%, secret=%, service=%)', __result_id, __result_secret, __result_service;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: get_outbound_api_key_secret_by_id retrieves encrypted secret by id
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_secret bytea;
BEGIN
    RAISE NOTICE 'TEST 8: get_outbound_api_key_secret_by_id retrieves secret by id';

    SELECT r.__api_key_id, r.__encrypted_secret
    FROM auth.get_outbound_api_key_secret_by_id('oak_test', 1, 'oak-corr-secret2', current_setting('test.oak_key1_id')::int) r
    INTO __result_id, __result_secret;

    IF __result_id IS NOT NULL AND __result_secret = '\xDEADBEEF'::bytea THEN
        RAISE NOTICE '  PASS: secret by id retrieved (id=%)', __result_id;
    ELSE
        RAISE EXCEPTION '  FAIL: secret by id mismatch (id=%, secret=%)', __result_id, __result_secret;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: update_outbound_api_key modifies title, description, service_url
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_title text;
    __result_desc text;
    __result_url text;
    __result_extra jsonb;
BEGIN
    RAISE NOTICE 'TEST 9: update_outbound_api_key modifies fields';

    SELECT r.__api_key_id, r.__title, r.__description, r.__service_url, r.__extra_data
    FROM auth.update_outbound_api_key(
        'oak_test', 1, 'oak-corr-upd1',
        current_setting('test.oak_key1_id')::int,
        'Updated Outbound Key 1',
        'Updated description',
        'https://api.alpha-v2.example.com',
        '{"header": "Authorization"}'::jsonb,
        null,
        'updated@test.com'
    ) r
    INTO __result_id, __result_title, __result_desc, __result_url, __result_extra;

    IF __result_title = 'Updated Outbound Key 1'
       AND __result_desc = 'Updated description'
       AND __result_url = 'https://api.alpha-v2.example.com'
       AND (__result_extra->>'header') = 'Authorization' THEN
        RAISE NOTICE '  PASS: updated (title=%, url=%, extra=%)', __result_title, __result_url, __result_extra;
    ELSE
        RAISE EXCEPTION '  FAIL: update mismatch (title=%, desc=%, url=%)', __result_title, __result_desc, __result_url;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: update_outbound_api_key journals event 14002
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 10: update_outbound_api_key journals event 14002';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 14002
      AND j.created_by = 'oak_test'
      AND j.correlation_id = 'oak-corr-upd1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL
       AND __journal_payload->>'key_type' = 'outbound'
       AND __journal_payload->>'api_key_title' = 'Updated Outbound Key 1' THEN
        RAISE NOTICE '  PASS: update journal entry correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: update_outbound_api_key_secret rotates encrypted secret
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_service text;
    __new_secret bytea;
BEGIN
    RAISE NOTICE 'TEST 11: update_outbound_api_key_secret rotates secret';

    SELECT r.__api_key_id, r.__service_code
    FROM auth.update_outbound_api_key_secret(
        'oak_test', 1, 'oak-corr-rot1',
        current_setting('test.oak_key1_id')::int,
        '\xCAFEBABE'::bytea
    ) r
    INTO __result_id, __result_service;

    IF __result_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: update_outbound_api_key_secret returned NULL';
    END IF;

    -- verify new secret stored
    SELECT ak.encrypted_secret
    FROM auth.api_key ak
    WHERE ak.api_key_id = __result_id
    INTO __new_secret;

    IF __new_secret = '\xCAFEBABE'::bytea AND __result_service = 'oaksvc_alpha' THEN
        RAISE NOTICE '  PASS: secret rotated (id=%, service=%)', __result_id, __result_service;
    ELSE
        RAISE EXCEPTION '  FAIL: secret rotation mismatch (secret=%, service=%)', __new_secret, __result_service;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: update_outbound_api_key_secret rejects null encrypted_secret
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 12: update_outbound_api_key_secret rejects null secret';

    BEGIN
        PERFORM auth.update_outbound_api_key_secret(
            'oak_test', 1, 'oak-corr-rot-err',
            current_setting('test.oak_key1_id')::int,
            null
        );
        RAISE EXCEPTION '  FAIL: should have raised exception for null secret';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Encrypted secret is required%' THEN
            RAISE NOTICE '  PASS: correctly rejected null secret (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 13: update_outbound_api_key_secret journals secret rotation
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 13: update_outbound_api_key_secret journals rotation';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 14002
      AND j.created_by = 'oak_test'
      AND j.correlation_id = 'oak-corr-rot1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL
       AND __journal_payload->>'action' = 'secret_rotated'
       AND __journal_payload->>'key_type' = 'outbound'
       AND __journal_payload->>'service_code' = 'oaksvc_alpha' THEN
        RAISE NOTICE '  PASS: rotation journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: create second outbound key for delete test
-- ============================================================================
DO $$
DECLARE
    __api_key_id int;
BEGIN
    RAISE NOTICE 'TEST 14: create second outbound key for delete test';

    SELECT r.__api_key_id
    FROM auth.create_outbound_api_key(
        'oak_test', 1, 'oak-corr-2',
        'Test Outbound Key 2', 'Second key for delete',
        'oaksvc_beta',
        '\xBEEFCAFE'::bytea
    ) r
    INTO __api_key_id;

    IF __api_key_id IS NOT NULL THEN
        PERFORM set_config('test.oak_key2_id', __api_key_id::text, false);
        RAISE NOTICE '  PASS: second outbound key created (id=%)', __api_key_id;
    ELSE
        RAISE EXCEPTION '  FAIL: create returned NULL';
    END IF;
END $$;

-- ============================================================================
-- TEST 15: delete_outbound_api_key removes the key
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_service text;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 15: delete_outbound_api_key removes the key';

    SELECT r.__api_key_id, r.__service_code
    FROM auth.delete_outbound_api_key('oak_test', 1, 'oak-corr-del1', current_setting('test.oak_key2_id')::int) r
    INTO __result_id, __result_service;

    IF __result_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: delete returned NULL';
    END IF;

    SELECT count(*)
    FROM auth.api_key
    WHERE api_key_id = __result_id
    INTO __count;

    IF __count = 0 AND __result_service = 'oaksvc_beta' THEN
        RAISE NOTICE '  PASS: key deleted (id=%, service=%)', __result_id, __result_service;
    ELSE
        RAISE EXCEPTION '  FAIL: key still exists (count=%, service=%)', __count, __result_service;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: delete_outbound_api_key journals event 14003
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 16: delete_outbound_api_key journals event 14003';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 14003
      AND j.created_by = 'oak_test'
      AND j.correlation_id = 'oak-corr-del1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL
       AND __journal_payload->>'key_type' = 'outbound'
       AND __journal_payload->>'service_code' = 'oaksvc_beta' THEN
        RAISE NOTICE '  PASS: delete journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: delete_outbound_api_key raises for non-existent key
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 17: delete_outbound_api_key raises for non-existent key';

    BEGIN
        PERFORM auth.delete_outbound_api_key('oak_test', 1, 'oak-corr-del-err', 999999);
        RAISE EXCEPTION '  FAIL: should have raised exception for non-existent key';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Outbound API key not found%' THEN
            RAISE NOTICE '  PASS: correctly raised not found (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 18: update_outbound_api_key_secret raises for non-existent key
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 18: update_outbound_api_key_secret raises for non-existent key';

    BEGIN
        PERFORM auth.update_outbound_api_key_secret('oak_test', 1, 'oak-corr-rot-err2', 999999, '\xAAAA'::bytea);
        RAISE EXCEPTION '  FAIL: should have raised exception for non-existent key';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%Outbound API key not found%' THEN
            RAISE NOTICE '  PASS: correctly raised not found (%)', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: unexpected error: %', SQLERRM;
        END IF;
    END;
END $$;
