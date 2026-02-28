set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up journal entries created by tests
    DELETE FROM journal WHERE created_by = 'test_ecm';

    -- Clean up any leftover test event messages
    DELETE FROM const.event_message WHERE created_by = 'test_ecm';

    -- Clean up any leftover test event codes
    DELETE FROM const.event_code WHERE event_id BETWEEN 90001 AND 90999;

    -- Clean up test category
    DELETE FROM const.event_category WHERE category_code = 'test_app_event';

    RAISE NOTICE 'CLEANUP: Done';
END $$;
