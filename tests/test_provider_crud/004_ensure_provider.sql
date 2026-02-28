set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 8: ensure_provider returns existing provider without creating new
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __is_new boolean;
    __expected_id int;
BEGIN
    RAISE NOTICE 'TEST 8: ensure_provider returns existing provider';

    SELECT provider_id INTO __expected_id FROM auth.provider WHERE code = 'prov_test_1';

    SELECT p.__provider_id, p.__is_new
    FROM auth.ensure_provider('prov_test', 1, 'prov-test-ens', 'prov_test_1', 'Should Not Update Name') p
    INTO __provider_id, __is_new;

    IF __provider_id = __expected_id AND __is_new = false THEN
        RAISE NOTICE '  PASS: returned existing (id=%, is_new=%)', __provider_id, __is_new;
    ELSE
        RAISE EXCEPTION '  FAIL: expected existing id=%, is_new=false, got id=%, is_new=%',
            __expected_id, __provider_id, __is_new;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: ensure_provider creates new provider when not found
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __is_new boolean;
    __db_code text;
BEGIN
    RAISE NOTICE 'TEST 9: ensure_provider creates new provider when not found';

    SELECT p.__provider_id, p.__is_new
    FROM auth.ensure_provider('prov_test', 1, 'prov-test-ens2', 'prov_test_ensure', 'Ensure Test Provider') p
    INTO __provider_id, __is_new;

    IF __provider_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: ensure_provider returned NULL';
    END IF;

    SELECT code INTO __db_code FROM auth.provider WHERE provider_id = __provider_id;

    IF __is_new = true AND __db_code = 'prov_test_ensure' THEN
        RAISE NOTICE '  PASS: created new (id=%, is_new=%, code=%)', __provider_id, __is_new, __db_code;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_new=true, code=prov_test_ensure, got is_new=%, code=%',
            __is_new, __db_code;
    END IF;
END $$;
