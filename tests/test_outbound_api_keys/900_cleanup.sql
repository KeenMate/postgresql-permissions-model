set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.api_key WHERE created_by = 'oak_test';
    DELETE FROM auth.user_info WHERE username LIKE 'api_key_outbound_oaksvc_%';
    DELETE FROM public.journal WHERE created_by = 'oak_test';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Outbound API Keys Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 25 tests passed:';
    RAISE NOTICE '  1.  create_outbound_api_key returns valid api_key_id';
    RAISE NOTICE '  2.  create_outbound_api_key journals event 14001';
    RAISE NOTICE '  3.  create_outbound_api_key rejects null service_code';
    RAISE NOTICE '  4.  create_outbound_api_key rejects null encrypted_secret';
    RAISE NOTICE '  5.  get_outbound_api_key retrieves by service_code';
    RAISE NOTICE '  6.  get_outbound_api_key_by_id retrieves by id';
    RAISE NOTICE '  7.  get_outbound_api_key_secret retrieves encrypted secret';
    RAISE NOTICE '  8.  get_outbound_api_key_secret_by_id retrieves secret by id';
    RAISE NOTICE '  9.  update_outbound_api_key modifies fields';
    RAISE NOTICE '  10. update_outbound_api_key journals event 14002';
    RAISE NOTICE '  11. update_outbound_api_key_secret rotates secret';
    RAISE NOTICE '  12. update_outbound_api_key_secret rejects null secret';
    RAISE NOTICE '  13. update_outbound_api_key_secret journals rotation';
    RAISE NOTICE '  14. create second outbound key for delete test';
    RAISE NOTICE '  15. delete_outbound_api_key removes the key';
    RAISE NOTICE '  16. delete_outbound_api_key journals event 14003';
    RAISE NOTICE '  17. delete_outbound_api_key raises for non-existent key';
    RAISE NOTICE '  18. update_outbound_api_key_secret raises for non-existent key';
    RAISE NOTICE '  19. create additional outbound keys for search';
    RAISE NOTICE '  20. search_outbound_api_keys returns all outbound keys';
    RAISE NOTICE '  21. search_outbound_api_keys filters by service_code';
    RAISE NOTICE '  22. search_outbound_api_keys filters by search_text';
    RAISE NOTICE '  23. search_outbound_api_keys pagination works';
    RAISE NOTICE '  24. search_outbound_api_keys returns empty for no match';
    RAISE NOTICE '  25. service_code is stored in lowercase';
    RAISE NOTICE '';
END $$;
