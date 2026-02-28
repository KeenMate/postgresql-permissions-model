set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Cleanup is handled automatically by transaction rollback (isolation: "transaction").
-- This file runs after rollback on the real database.
DO $$
BEGIN
    RAISE NOTICE 'CLEANUP: Transaction rollback handled all test data cleanup';
END;
$$;
