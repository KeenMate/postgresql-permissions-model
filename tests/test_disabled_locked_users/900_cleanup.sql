set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Transaction rollback handles data cleanup
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Disabled/Locked Users Tests - COMPLETED';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'CLEANUP: Transaction rollback will handle data cleanup';
END $$;
