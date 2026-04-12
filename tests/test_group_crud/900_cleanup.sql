set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up in reverse dependency order
    DELETE FROM auth.permission_assignment WHERE created_by = 'grp_crud_test';
    DELETE FROM auth.user_permission_cache WHERE created_by = 'grp_crud_test';
    DELETE FROM auth.user_group_mapping WHERE provider_code = 'grp_crud_prov';
    DELETE FROM auth.user_group_member WHERE created_by = 'grp_crud_test';
    DELETE FROM auth.user_group WHERE created_by = 'grp_crud_test';
    DELETE FROM auth.permission WHERE code = 'grp_crud_test_perm';
    DELETE FROM auth.provider WHERE code = 'grp_crud_prov';
    DELETE FROM public.journal WHERE created_by = 'grp_crud_test';
    DELETE FROM auth.user_info WHERE username = 'grp_crud_target';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Group CRUD Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 9 tests passed:';
    RAISE NOTICE '  1. create_user_group - create group';
    RAISE NOTICE '  2. update_user_group - update title';
    RAISE NOTICE '  3. create_user_group_member - add member';
    RAISE NOTICE '  4. delete_user_group_member - remove member';
    RAISE NOTICE '  5. delete_user_group_mapping - create then delete';
    RAISE NOTICE '  6. delete_user_group - delete non-system group';
    RAISE NOTICE '  7. get_effective_group_permissions - assign and verify';
    RAISE NOTICE '  8. get_assigned_group_permissions - verify assigned';
    RAISE NOTICE '  9. unassign from group and verify empty';
    RAISE NOTICE '';
END $$;
