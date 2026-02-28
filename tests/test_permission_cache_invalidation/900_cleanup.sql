set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up in reverse order of dependencies
    DELETE FROM auth.permission_assignment WHERE created_by = 'test';
    DELETE FROM auth.user_permission_cache WHERE created_by = 'test';
    DELETE FROM auth.owner WHERE created_by = 'test';
    DELETE FROM auth.user_group_member WHERE created_by = 'test';
    DELETE FROM auth.perm_set_perm WHERE created_by = 'test';
    DELETE FROM auth.perm_set WHERE code = 'cache_test_perm_set';
    DELETE FROM auth.permission WHERE code = 'cache_test_perm';
    DELETE FROM auth.user_group WHERE code = 'cache_test_group';
    DELETE FROM auth.user_info WHERE username = 'cache_test_user';

    RAISE NOTICE 'CLEANUP: Done';
END $$;
