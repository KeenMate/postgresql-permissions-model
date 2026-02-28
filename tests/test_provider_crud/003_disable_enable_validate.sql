set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 4: disable_provider sets is_active=false, returns provider_id, journals 16005
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __returned_id int;
    __db_active boolean;
    __journal_keys jsonb;
BEGIN
    RAISE NOTICE 'TEST 4: disable_provider sets is_active=false and journals 16005';

    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_1';

    SELECT p.__provider_id
    FROM auth.disable_provider('prov_test', 1, 'prov-test-dis', 'prov_test_1') p
    INTO __returned_id;

    IF __returned_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: disable_provider returned NULL';
    END IF;

    IF __returned_id != __provider_id THEN
        RAISE EXCEPTION '  FAIL: disable_provider returned % (expected %)', __returned_id, __provider_id;
    END IF;

    SELECT is_active INTO __db_active FROM auth.provider WHERE provider_id = __provider_id;

    IF __db_active != false THEN
        RAISE EXCEPTION '  FAIL: is_active still true after disable';
    END IF;

    SELECT j.keys
    FROM public.journal j
    WHERE j.event_id = 16005
      AND j.correlation_id = 'prov-test-dis'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys;

    IF __journal_keys IS NOT NULL AND (__journal_keys->>'provider')::int = __provider_id THEN
        RAISE NOTICE '  PASS: disabled and journaled (id=%, active=%, journal_keys=%)', __returned_id, __db_active, __journal_keys;
    ELSE
        RAISE EXCEPTION '  FAIL: journal entity_id is NULL or missing (keys=%)', __journal_keys;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: validate_provider_is_active raises error for inactive provider
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 5: validate_provider_is_active raises error for inactive provider';

    -- prov_test_1 was disabled in test 4
    BEGIN
        PERFORM auth.validate_provider_is_active('prov_test_1');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown for inactive provider';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = '33010' THEN
                RAISE NOTICE '  PASS: Correctly raised error for inactive provider';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 6: enable_provider sets is_active=true, returns provider_id, journals 16004
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __returned_id int;
    __db_active boolean;
    __journal_keys jsonb;
BEGIN
    RAISE NOTICE 'TEST 6: enable_provider sets is_active=true and journals 16004';

    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_1';

    SELECT p.__provider_id
    FROM auth.enable_provider('prov_test', 1, 'prov-test-ena', 'prov_test_1') p
    INTO __returned_id;

    IF __returned_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: enable_provider returned NULL';
    END IF;

    IF __returned_id != __provider_id THEN
        RAISE EXCEPTION '  FAIL: enable_provider returned % (expected %)', __returned_id, __provider_id;
    END IF;

    SELECT is_active INTO __db_active FROM auth.provider WHERE provider_id = __provider_id;

    IF __db_active != true THEN
        RAISE EXCEPTION '  FAIL: is_active still false after enable';
    END IF;

    SELECT j.keys
    FROM public.journal j
    WHERE j.event_id = 16004
      AND j.correlation_id = 'prov-test-ena'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys;

    IF __journal_keys IS NOT NULL AND (__journal_keys->>'provider')::int = __provider_id THEN
        RAISE NOTICE '  PASS: enabled and journaled (id=%, active=%, journal_keys=%)', __returned_id, __db_active, __journal_keys;
    ELSE
        RAISE EXCEPTION '  FAIL: journal entity_id is NULL or missing (keys=%)', __journal_keys;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: validate_provider_is_active passes for active provider
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 7: validate_provider_is_active passes for active provider';

    -- prov_test_1 was re-enabled in test 6
    PERFORM auth.validate_provider_is_active('prov_test_1');
    RAISE NOTICE '  PASS: No error raised for active provider';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '  FAIL: Unexpected error for active provider: % %', SQLSTATE, SQLERRM;
END $$;
