set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Provider CRUD Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Clean any leftover test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'SETUP: Cleaning leftover test data...';

    DELETE FROM auth.user_group_mapping WHERE provider_code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');
    DELETE FROM auth.user_identity WHERE provider_code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');
    DELETE FROM public.journal WHERE created_by = 'prov_test';
    DELETE FROM auth.user_group WHERE code IN ('prov_test_cap_group');
    DELETE FROM auth.provider WHERE code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');

    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
