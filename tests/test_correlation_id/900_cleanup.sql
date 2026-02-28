set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Transaction rollback handles data cleanup, this is just a notice
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Correlation ID Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 5 tests passed:';
    RAISE NOTICE '  1. Correlation ID flows to public.journal';
    RAISE NOTICE '  2. Correlation ID flows to auth.user_event';
    RAISE NOTICE '  3. search_journal filters by correlation_id';
    RAISE NOTICE '  4. search_user_events filters by correlation_id';
    RAISE NOTICE '  5. Null correlation_id backwards compatibility';
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Transaction rollback will handle data cleanup';
END $$;
