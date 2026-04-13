set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Outbound API Keys Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Clean any leftover test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'SETUP: Cleaning leftover test data...';

    DELETE FROM auth.api_key WHERE created_by = 'oak_test';
    DELETE FROM auth.user_info WHERE username LIKE 'api_key_outbound_oaksvc_%';
    DELETE FROM public.journal WHERE created_by = 'oak_test';

    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
