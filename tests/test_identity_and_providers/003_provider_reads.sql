set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 12: get_providers returns at least the email provider
-- ============================================================================
DO $$
DECLARE
    __email_found boolean := false;
    __corr_id text := 'idp-providers-' || gen_random_uuid()::text;
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 12: get_providers returns at least the email provider';

    FOR __rec IN
        SELECT * FROM auth.get_providers(1, __corr_id)
    LOOP
        IF __rec.__code = 'email' THEN
            __email_found := true;
        END IF;
    END LOOP;

    IF __email_found THEN
        RAISE NOTICE '  PASS: email provider found in get_providers result';
    ELSE
        RAISE EXCEPTION '  FAIL: email provider not found in get_providers result';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: get_providers returns our test_idp provider
-- ============================================================================
DO $$
DECLARE
    __test_idp_found boolean := false;
    __corr_id text := 'idp-providers2-' || gen_random_uuid()::text;
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 13: get_providers returns test_idp provider';

    FOR __rec IN
        SELECT * FROM auth.get_providers(1, __corr_id)
    LOOP
        IF __rec.__code = 'test_idp' THEN
            __test_idp_found := true;
        END IF;
    END LOOP;

    IF __test_idp_found THEN
        RAISE NOTICE '  PASS: test_idp provider found in get_providers result';
    ELSE
        RAISE EXCEPTION '  FAIL: test_idp provider not found in get_providers result';
    END IF;
END $$;

-- ============================================================================
-- TEST 14: get_providers filters by is_active
-- ============================================================================
DO $$
DECLARE
    __count int;
    __corr_id text := 'idp-providers3-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 14: get_providers filters by is_active';

    SELECT count(*) INTO __count
    FROM auth.get_providers(1, __corr_id, _is_active := true);

    IF __count > 0 THEN
        RAISE NOTICE '  PASS: get_providers with is_active=true returned % providers', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected at least 1 active provider, got %', __count;
    END IF;
END $$;
