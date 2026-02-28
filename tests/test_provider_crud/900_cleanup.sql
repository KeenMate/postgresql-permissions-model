set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_group_mapping WHERE provider_code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');
    DELETE FROM auth.user_identity WHERE provider_code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');
    DELETE FROM public.journal WHERE created_by = 'prov_test';
    DELETE FROM auth.user_info WHERE username = 'prov_test_user_1';
    DELETE FROM auth.user_group WHERE code IN ('prov_test_cap_group');
    DELETE FROM auth.provider WHERE code IN ('prov_test_1', 'prov_test_2', 'prov_test_ensure', 'prov_test_cap');

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Provider CRUD Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 19 tests passed:';
    RAISE NOTICE '  1.  create_provider returns valid provider_id';
    RAISE NOTICE '  2.  create_provider journals event 16001 with entity_id';
    RAISE NOTICE '  3.  update_provider modifies fields and journals 16002';
    RAISE NOTICE '  4.  disable_provider returns provider_id and journals 16005';
    RAISE NOTICE '  5.  validate_provider_is_active raises error for inactive';
    RAISE NOTICE '  6.  enable_provider returns provider_id and journals 16004';
    RAISE NOTICE '  7.  validate_provider_is_active passes for active';
    RAISE NOTICE '  8.  ensure_provider returns existing without creating new';
    RAISE NOTICE '  9.  ensure_provider creates new when not found';
    RAISE NOTICE '  10. get_provider_users returns linked users';
    RAISE NOTICE '  11. delete_provider returns provider_id and journals 16003';
    RAISE NOTICE '  12. delete_provider for non-existent code returns no rows';
    RAISE NOTICE '  13. create_provider with capability flags stores them';
    RAISE NOTICE '  14. update_provider modifies capability flags and journals';
    RAISE NOTICE '  15. validate_provider_allows_group_mapping raises 33016';
    RAISE NOTICE '  16. validate_provider_allows_group_mapping passes when true';
    RAISE NOTICE '  17. validate_provider_allows_group_sync raises 33017';
    RAISE NOTICE '  18. validate_provider_allows_group_sync passes when true';
    RAISE NOTICE '  19. create_user_group_mapping rejects non-mapping provider';
    RAISE NOTICE '';
END $$;
