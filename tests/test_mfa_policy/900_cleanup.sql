set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Transaction rollback handles cleanup (isolation: transaction)
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Cleanup --';
    RAISE NOTICE 'Transaction rollback will clean up all test data.';
END $$;
