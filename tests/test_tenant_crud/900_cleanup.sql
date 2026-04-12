set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
DECLARE
    __ug_tenant_id int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Delete test tenants (cascades groups, owners, etc.)
    __ug_tenant_id := nullif(current_setting('test_tenant.ug_tenant_id', true), '')::int;
    IF __ug_tenant_id IS NOT NULL THEN
        DELETE FROM auth.tenant WHERE tenant_id = __ug_tenant_id;
    END IF;

    -- Delete journal entries created by tests
    DELETE FROM public.journal WHERE created_by = 'tenant_test';

    -- Delete permission assignments for test users
    DELETE FROM auth.permission_assignment
    WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username IN ('tenant_test_admin', 'tenant_test_member'));

    -- Delete test users
    DELETE FROM auth.user_permission_cache
    WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username IN ('tenant_test_admin', 'tenant_test_member'));

    DELETE FROM auth.user_info WHERE username IN ('tenant_test_admin', 'tenant_test_member');

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Tenant CRUD Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 22 tests passed:';
    RAISE NOTICE '  1.  create_tenant returns valid tenant_id and uuid';
    RAISE NOTICE '  2.  create_tenant creates default groups';
    RAISE NOTICE '  3.  create_tenant journals event 11001';
    RAISE NOTICE '  4.  tenant row exists in auth.tenant';
    RAISE NOTICE '  5.  update_tenant modifies title and code';
    RAISE NOTICE '  6.  update_tenant journals event 11002';
    RAISE NOTICE '  7.  search_tenants finds the created tenant';
    RAISE NOTICE '  8.  search_tenants pagination works';
    RAISE NOTICE '  9.  delete_tenant removes the tenant';
    RAISE NOTICE '  10. delete_tenant cascades groups';
    RAISE NOTICE '  11. create tenant for user/group tests';
    RAISE NOTICE '  12. add user to tenant via group membership';
    RAISE NOTICE '  13. get_tenant_users returns the added user';
    RAISE NOTICE '  14. create additional group in tenant';
    RAISE NOTICE '  15. get_tenant_groups returns groups for tenant';
    RAISE NOTICE '  16. create_owner assigns tenant owner';
    RAISE NOTICE '  17. owner row exists in auth.owner';
    RAISE NOTICE '  18. is_owner returns true for assigned owner';
    RAISE NOTICE '  19. is_owner returns false for non-owner';
    RAISE NOTICE '  20. create_owner journals event 11010';
    RAISE NOTICE '  21. delete_owner removes the ownership';
    RAISE NOTICE '  22. is_owner returns false after owner deleted';
    RAISE NOTICE '';
END $$;
