set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_event WHERE created_by = 'test_search';
    DELETE FROM public.journal WHERE created_by = 'test_search';
    DELETE FROM auth.api_key WHERE created_by = 'test_search';
    DELETE FROM auth.user_info WHERE username = 'search_test_user';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Search Functions Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 14 tests passed:';
    RAISE NOTICE '  1. search_api_keys executes without error';
    RAISE NOTICE '  2. search_api_keys filters by search text';
    RAISE NOTICE '  3. search_api_keys returns empty for non-matching text';
    RAISE NOTICE '  4. search_outbound_api_keys executes without error';
    RAISE NOTICE '  5. search_outbound_api_keys filters by service_code';
    RAISE NOTICE '  6. search_users executes without error';
    RAISE NOTICE '  7. search_users filters by search text';
    RAISE NOTICE '  8. search_user_groups executes without error';
    RAISE NOTICE '  9. search_permissions executes without error';
    RAISE NOTICE '  10. search_perm_sets executes without error';
    RAISE NOTICE '  11. search_tenants executes without error';
    RAISE NOTICE '  12. search_journal executes without error';
    RAISE NOTICE '  13. search_user_events executes without error';
    RAISE NOTICE '  14. Pagination limits results';
    RAISE NOTICE '';
END $$;
