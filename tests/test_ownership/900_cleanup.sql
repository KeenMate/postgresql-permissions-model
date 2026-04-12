set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Cleanup is handled automatically by transaction rollback (isolation: "transaction").
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Transaction rollback handled all test data cleanup';
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Ownership Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 16 tests passed:';
    RAISE NOTICE '  1.  create_owner assigns tenant owner';
    RAISE NOTICE '  2.  is_owner returns true for assigned tenant owner';
    RAISE NOTICE '  3.  has_owner returns true for tenant with owner';
    RAISE NOTICE '  4.  owner row exists in auth.owner with correct data';
    RAISE NOTICE '  5.  create_owner journals event 11010';
    RAISE NOTICE '  6.  delete_owner with NULL group_id is a no-op (SQL NULL != NULL)';
    RAISE NOTICE '  7.  remove tenant owner via direct DELETE';
    RAISE NOTICE '  8.  is_owner returns false after owner removed';
    RAISE NOTICE '  9.  has_owner returns false for tenant without owners';
    RAISE NOTICE '  10. create_owner assigns group owner';
    RAISE NOTICE '  11. is_owner returns true for group owner';
    RAISE NOTICE '  12. is_owner with NULL group_id matches any ownership in tenant';
    RAISE NOTICE '  13. has_owner returns true for group with owner';
    RAISE NOTICE '  14. create_owner journals event 11010 for group owner';
    RAISE NOTICE '  15. delete_owner removes group owner and journals 11011';
    RAISE NOTICE '  16. has_owner returns false after group owner removed';
    RAISE NOTICE '';
END $$;
