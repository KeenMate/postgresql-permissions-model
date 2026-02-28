set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 15: validate_provider_allows_group_mapping raises 33016 when false
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 15: validate_provider_allows_group_mapping raises 33016 when false';

    -- prov_test_1 was created with defaults (allows_group_mapping=false)
    BEGIN
        PERFORM auth.validate_provider_allows_group_mapping('prov_test_1');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = '33016' THEN
                RAISE NOTICE '  PASS: Correctly raised 33016 for provider without group mapping';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 16: validate_provider_allows_group_mapping passes when true
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 16: validate_provider_allows_group_mapping passes when true';

    -- prov_test_cap has allows_group_mapping=true (updated in test 14)
    PERFORM auth.validate_provider_allows_group_mapping('prov_test_cap');
    RAISE NOTICE '  PASS: No error raised for provider with group mapping enabled';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ============================================================================
-- TEST 17: validate_provider_allows_group_sync raises 33017 when false
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 17: validate_provider_allows_group_sync raises 33017 when false';

    -- prov_test_cap has allows_group_sync=false (updated in test 14)
    BEGIN
        PERFORM auth.validate_provider_allows_group_sync('prov_test_cap');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = '33017' THEN
                RAISE NOTICE '  PASS: Correctly raised 33017 for provider without group sync';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 18: validate_provider_allows_group_sync passes when true
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
BEGIN
    RAISE NOTICE 'TEST 18: validate_provider_allows_group_sync passes when true';

    -- Re-enable sync on prov_test_cap
    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_cap';
    PERFORM auth.update_provider('prov_test', 1, 'prov-test-cap-sync', __provider_id, 'prov_test_cap', 'Provider Cap Test', true, true, true);

    PERFORM auth.validate_provider_allows_group_sync('prov_test_cap');
    RAISE NOTICE '  PASS: No error raised for provider with group sync enabled';
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ============================================================================
-- TEST 19: create_user_group_mapping rejects provider with allows_group_mapping=false
-- ============================================================================
DO $$
DECLARE
    __group_id int;
BEGIN
    RAISE NOTICE 'TEST 19: create_user_group_mapping rejects non-mapping provider';

    -- Create a test group for the mapping attempt
    INSERT INTO auth.user_group (created_by, updated_by, title, code, tenant_id)
    VALUES ('prov_test', 'prov_test', 'Cap Test Group', 'prov_test_cap_group', 1)
    ON CONFLICT (code, tenant_id) DO UPDATE SET title = 'Cap Test Group'
    RETURNING user_group_id INTO __group_id;

    -- prov_test_1 has allows_group_mapping=false (default)
    BEGIN
        PERFORM auth.create_user_group_mapping('prov_test', 1, 'prov-test-map-reject', __group_id, 'prov_test_1', 'some_group_id', 'Some Group');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = '33016' THEN
                RAISE NOTICE '  PASS: Correctly rejected mapping for non-mapping provider (group_id=%)', __group_id;
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;
