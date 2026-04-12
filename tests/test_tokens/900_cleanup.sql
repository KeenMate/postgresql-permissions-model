set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.token WHERE created_by = 'tok_test';
    DELETE FROM public.journal WHERE created_by = 'tok_test';
    DELETE FROM auth.permission_assignment WHERE created_by = 'tok_test';
    DELETE FROM auth.user_permission_cache WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE 'tok_test_%');
    DELETE FROM auth.user_data WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE 'tok_test_%');
    DELETE FROM auth.user_info WHERE username LIKE 'tok_test_%';

    DROP TABLE IF EXISTS _tok_test_data;

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Token CRUD Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 15 tests passed:';
    RAISE NOTICE '  1.  create_token returns valid token_id, uid, and expires_at';
    RAISE NOTICE '  2.  create_token journals event 15001';
    RAISE NOTICE '  3.  validate_token succeeds for valid token';
    RAISE NOTICE '  4.  set_token_as_used marks token and returns correct state';
    RAISE NOTICE '  5.  validate_token fails for already-used token';
    RAISE NOTICE '  6.  create_token with custom expiration';
    RAISE NOTICE '  7.  create_token with token_data stores jsonb payload';
    RAISE NOTICE '  8.  create_token invalidates previous valid tokens of same type';
    RAISE NOTICE '  9.  validate_token fails for non-existent token';
    RAISE NOTICE '  10. validate_token with _set_as_used=true marks token as used';
    RAISE NOTICE '  11. set_token_as_failed marks token with validation_failed state';
    RAISE NOTICE '  12. expired token fails validation';
    RAISE NOTICE '  13. validate_token with wrong user raises error';
    RAISE NOTICE '  14. duplicate token value raises error';
    RAISE NOTICE '  15. set_token_as_used_by_token works without providing uid';
    RAISE NOTICE '';
END $$;
