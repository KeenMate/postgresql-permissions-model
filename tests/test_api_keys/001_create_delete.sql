set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_api_key returns api_key_id, api_key, and api_secret
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __api_key text;
    __api_secret text;
    __db_title text;
    __db_tenant_id int;
BEGIN
    RAISE NOTICE 'TEST 1: create_api_key returns api_key_id, api_key, and api_secret';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    SELECT r.__api_key_id, r.__api_key, r.__api_secret
    FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-create',
        'Test Key 1', 'Test key description',
        null, null,
        _tenant_id := 1
    ) r
    INTO __api_key_id, __api_key, __api_secret;

    IF __api_key_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_api_key returned NULL api_key_id';
    END IF;
    IF __api_key IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_api_key returned NULL api_key';
    END IF;
    IF __api_secret IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_api_key returned NULL api_secret';
    END IF;

    -- Verify row in auth.api_key
    SELECT title, tenant_id
    FROM auth.api_key
    WHERE api_key_id = __api_key_id
    INTO __db_title, __db_tenant_id;

    IF __db_title = 'Test Key 1' AND __db_tenant_id = 1 THEN
        RAISE NOTICE '  PASS: api_key created (id=%, key=%, title=%, tenant=%)', __api_key_id, __api_key, __db_title, __db_tenant_id;
    ELSE
        RAISE EXCEPTION '  FAIL: api_key data mismatch (title=%, tenant=%)', __db_title, __db_tenant_id;
    END IF;

    -- Store for later tests
    INSERT INTO _ak_test_data VALUES ('key1_id', __api_key_id::text)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _ak_test_data VALUES ('key1_key', __api_key)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
    INSERT INTO _ak_test_data VALUES ('key1_secret', __api_secret)
        ON CONFLICT (key) DO UPDATE SET val = EXCLUDED.val;
END $$;

-- ============================================================================
-- TEST 2: create_api_key also creates a technical user
-- ============================================================================
DO $$
DECLARE
    __api_key text;
    __tech_username text;
    __user_type text;
BEGIN
    RAISE NOTICE 'TEST 2: create_api_key creates a technical user';

    SELECT val INTO __api_key FROM _ak_test_data WHERE key = 'key1_key';
    __tech_username := 'api_key_' || __api_key;

    SELECT user_type_code
    FROM auth.user_info
    WHERE code = __tech_username
    INTO __user_type;

    IF __user_type = 'api' THEN
        RAISE NOTICE '  PASS: technical user created (username=%, type=%)', __tech_username, __user_type;
    ELSE
        RAISE EXCEPTION '  FAIL: technical user not found or wrong type (username=%, type=%)', __tech_username, __user_type;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: create_api_key journals event 14001
-- ============================================================================
DO $$
DECLARE
    __api_key_id int;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 3: create_api_key journals event 14001';

    SELECT val::int INTO __api_key_id FROM _ak_test_data WHERE key = 'key1_id';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 14001
      AND j.created_by = 'ak_test'
      AND j.correlation_id = 'ak-test-create'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NULL THEN
        RAISE EXCEPTION '  FAIL: no journal entry found for event 14001';
    END IF;

    IF __journal_payload->>'api_key_title' = 'Test Key 1' THEN
        RAISE NOTICE '  PASS: journal entry found (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal payload mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: delete_api_key removes the key and returns api_key_id
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __api_key_id int;
    __returned_id int;
    __count int;
    __api_key text;
    __tech_count int;
BEGIN
    RAISE NOTICE 'TEST 4: delete_api_key removes key and technical user';

    SELECT val::bigint INTO __admin_id FROM _ak_test_data WHERE key = 'admin_id';

    -- Create a key specifically for deletion
    SELECT r.__api_key_id, r.__api_key
    FROM auth.create_api_key(
        'ak_test', __admin_id, 'ak-test-del',
        'Key To Delete', 'Will be deleted',
        null, null, _tenant_id := 1
    ) r
    INTO __api_key_id, __api_key;

    -- Delete it
    SELECT r.__api_key_id
    FROM auth.delete_api_key('ak_test', __admin_id, 'ak-test-del', __api_key_id, 1) r
    INTO __returned_id;

    IF __returned_id IS NULL OR __returned_id != __api_key_id THEN
        RAISE EXCEPTION '  FAIL: delete_api_key returned % (expected %)', __returned_id, __api_key_id;
    END IF;

    -- Verify key is gone
    SELECT count(*) FROM auth.api_key WHERE api_key_id = __api_key_id INTO __count;
    IF __count != 0 THEN
        RAISE EXCEPTION '  FAIL: api_key still exists after delete (count=%)', __count;
    END IF;

    -- Verify technical user is also gone
    SELECT count(*) FROM auth.user_info WHERE code = 'api_key_' || __api_key INTO __tech_count;
    IF __tech_count != 0 THEN
        RAISE EXCEPTION '  FAIL: technical user still exists after delete (count=%)', __tech_count;
    END IF;

    RAISE NOTICE '  PASS: api_key and technical user deleted (id=%)', __returned_id;
END $$;
