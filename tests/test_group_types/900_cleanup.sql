set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_group_mapping WHERE provider_code = 'gt_test_prov';
    DELETE FROM auth.user_group_member WHERE created_by = 'gt_test';
    DELETE FROM public.journal WHERE created_by = 'gt_test';
    DELETE FROM auth.user_group WHERE code LIKE 'gt_test_%';
    DELETE FROM auth.provider WHERE code = 'gt_test_prov';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Group Types Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 20 tests passed:';
    RAISE NOTICE '  1.  newly created group is internal';
    RAISE NOTICE '  2.  set_user_group_as_external sets is_external=true';
    RAISE NOTICE '  3.  set_user_group_as_external removes manual members';
    RAISE NOTICE '  4.  set_user_group_as_external journals action=set_external';
    RAISE NOTICE '  5.  set_user_group_as_hybrid sets is_external=false';
    RAISE NOTICE '  6.  set_user_group_as_hybrid journals action=set_hybrid';
    RAISE NOTICE '  7.  set_user_group_as_internal removes non-manual members and mappings';
    RAISE NOTICE '  8.  set_user_group_as_internal journals action=set_internal';
    RAISE NOTICE '  9.  create_external_user_group creates group with mapping';
    RAISE NOTICE '  10. create_external_user_group with mapped_role';
    RAISE NOTICE '  11. round-trip type switching internal->external->hybrid->internal';
    RAISE NOTICE '  12. disable_user_group sets is_active=false';
    RAISE NOTICE '  13. disable_user_group journals action=disabled';
    RAISE NOTICE '  14. enable_user_group sets is_active=true';
    RAISE NOTICE '  15. enable_user_group journals action=enabled';
    RAISE NOTICE '  16. lock_user_group sets is_assignable=false';
    RAISE NOTICE '  17. lock_user_group journals action=locked';
    RAISE NOTICE '  18. unlock_user_group sets is_assignable=true';
    RAISE NOTICE '  19. unlock_user_group journals action=unlocked';
    RAISE NOTICE '  20. disable and lock are independent flags';
    RAISE NOTICE '';
END $$;
