set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up in reverse dependency order
    DELETE FROM auth.permission_assignment WHERE created_by = 'perm_crud_test';
    DELETE FROM auth.user_permission_cache WHERE created_by = 'perm_crud_test';
    DELETE FROM auth.perm_set_perm WHERE created_by = 'perm_crud_test';
    DELETE FROM auth.perm_set WHERE created_by = 'perm_crud_test';
    DELETE FROM public.translation WHERE created_by = 'perm_crud_test';
    DELETE FROM auth.permission WHERE created_by = 'perm_crud_test';
    DELETE FROM public.journal WHERE created_by = 'perm_crud_test';
    DELETE FROM auth.user_info WHERE username = 'perm_crud_target';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission CRUD Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 16 tests passed:';
    RAISE NOTICE '  1.  create_permission - root permission';
    RAISE NOTICE '  2.  create_permission - child with parent';
    RAISE NOTICE '  3.  parent has_children after child creation';
    RAISE NOTICE '  4.  create_perm_set with permission';
    RAISE NOTICE '  5.  update_perm_set title';
    RAISE NOTICE '  6.  delete perm set via direct SQL';
    RAISE NOTICE '  7.  recreate perm set for assignment tests';
    RAISE NOTICE '  8.  assign_permission - perm set to user';
    RAISE NOTICE '  9.  assign_permission - individual permission to user';
    RAISE NOTICE '  10. get_user_permissions shows both assignments';
    RAISE NOTICE '  11. unassign_permission - perm set';
    RAISE NOTICE '  12. unassign_permission - individual permission';
    RAISE NOTICE '  13. get_user_permissions empty after unassignment';
    RAISE NOTICE '  14. copy_perm_set with NULL title (regression)';
    RAISE NOTICE '  15. copy_perm_set with custom title';
    RAISE NOTICE '  16. copied perm set inherits permissions';
    RAISE NOTICE '';
END $$;
