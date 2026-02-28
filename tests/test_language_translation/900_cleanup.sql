set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Delete test translations
    DELETE FROM public.translation WHERE data_group = 'ui_labels';

    -- Delete test languages (except 'en')
    DELETE FROM const.language WHERE code NOT IN ('en');

    -- Clean up test journal entries
    DELETE FROM journal WHERE correlation_id LIKE 'test-corr-%';

    RAISE NOTICE 'CLEANUP: Done';
END $$;
