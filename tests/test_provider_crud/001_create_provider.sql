set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: create_provider returns valid provider_id and inserts row
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __db_code text;
    __db_name text;
    __db_active boolean;
BEGIN
    RAISE NOTICE 'TEST 1: create_provider returns valid provider_id';

    SELECT p.__provider_id
    FROM auth.create_provider('prov_test', 1, 'prov-test-1', 'prov_test_1', 'Provider Test 1', true) p
    INTO __provider_id;

    IF __provider_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_provider returned NULL provider_id';
    END IF;

    SELECT code, name, is_active
    FROM auth.provider
    WHERE provider_id = __provider_id
    INTO __db_code, __db_name, __db_active;

    IF __db_code = 'prov_test_1' AND __db_name = 'Provider Test 1' AND __db_active = true THEN
        RAISE NOTICE '  PASS: provider created (id=%, code=%, name=%, active=%)', __provider_id, __db_code, __db_name, __db_active;
    ELSE
        RAISE EXCEPTION '  FAIL: provider data mismatch (code=%, name=%, active=%)', __db_code, __db_name, __db_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: create_provider journals event 16001 with correct entity_id
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __journal_keys jsonb;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 2: create_provider journals event 16001 with entity_id';

    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_1';

    SELECT j.keys, j.data_payload
    FROM public.journal j
    WHERE j.event_id = 16001
      AND j.created_by = 'prov_test'
      AND j.correlation_id = 'prov-test-1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys, __journal_payload;

    IF __journal_keys IS NULL THEN
        RAISE EXCEPTION '  FAIL: No journal entry found for event 16001';
    END IF;

    IF (__journal_keys->>'provider')::int = __provider_id
       AND __journal_payload->>'provider_code' = 'prov_test_1'
       AND __journal_payload->>'provider_name' = 'Provider Test 1' THEN
        RAISE NOTICE '  PASS: journal keys=%, payload=%', __journal_keys, __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (keys=%, payload=%, expected provider_id=%)',
            __journal_keys, __journal_payload, __provider_id;
    END IF;
END $$;
