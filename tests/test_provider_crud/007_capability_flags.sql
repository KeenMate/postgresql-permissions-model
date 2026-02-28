set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 13: create_provider with explicit capability flags stores them correctly
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __db_mapping boolean;
    __db_sync boolean;
BEGIN
    RAISE NOTICE 'TEST 13: create_provider with capability flags';

    SELECT p.__provider_id
    FROM auth.create_provider('prov_test', 1, 'prov-test-cap', 'prov_test_cap', 'Provider Cap Test', true, true, true) p
    INTO __provider_id;

    IF __provider_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_provider returned NULL';
    END IF;

    SELECT allows_group_mapping, allows_group_sync
    FROM auth.provider
    WHERE provider_id = __provider_id
    INTO __db_mapping, __db_sync;

    IF __db_mapping = true AND __db_sync = true THEN
        RAISE NOTICE '  PASS: capability flags stored (id=%, mapping=%, sync=%)', __provider_id, __db_mapping, __db_sync;
    ELSE
        RAISE EXCEPTION '  FAIL: capability flags mismatch (mapping=%, sync=%)', __db_mapping, __db_sync;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: update_provider modifies capability flags and journals them
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __returned_id int;
    __db_mapping boolean;
    __db_sync boolean;
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 14: update_provider modifies capability flags';

    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_cap';

    SELECT p.__provider_id
    FROM auth.update_provider('prov_test', 1, 'prov-test-cap-upd', __provider_id, 'prov_test_cap', 'Provider Cap Test', true, true, false) p
    INTO __returned_id;

    SELECT allows_group_mapping, allows_group_sync
    FROM auth.provider
    WHERE provider_id = __provider_id
    INTO __db_mapping, __db_sync;

    IF __db_mapping != true OR __db_sync != false THEN
        RAISE EXCEPTION '  FAIL: flags not updated (mapping=%, sync=%)', __db_mapping, __db_sync;
    END IF;

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 16002
      AND j.correlation_id = 'prov-test-cap-upd'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL
       AND (__journal_payload->>'allows_group_mapping')::boolean = true
       AND (__journal_payload->>'allows_group_sync')::boolean = false THEN
        RAISE NOTICE '  PASS: flags updated and journaled (mapping=%, sync=%, payload=%)', __db_mapping, __db_sync, __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;
