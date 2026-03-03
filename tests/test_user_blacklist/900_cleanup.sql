set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Summary (transaction rollback handles actual cleanup)
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'User Blacklist Tests - Complete';
    RAISE NOTICE '(transaction rollback handles cleanup)';
    RAISE NOTICE '=================================================================';
END $$;
