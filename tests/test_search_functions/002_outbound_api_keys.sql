set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 4: auth.search_outbound_api_keys executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 4: auth.search_outbound_api_keys executes without error';

    SELECT count(*) INTO __count FROM auth.search_outbound_api_keys(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_outbound_api_keys returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 5: auth.search_outbound_api_keys filters by service_code
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 5: auth.search_outbound_api_keys filters by service_code';

    SELECT count(*) INTO __count FROM auth.search_outbound_api_keys(1, null, _service_code := 'test_service');

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: found % outbound key(s) for service_code "test_service"', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 result, got %', __count;
    END IF;
END $$;
