set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'email' LIKE '%regtest%';
    DELETE FROM auth.user_event WHERE created_by IN ('reg_test', 'system') AND event_data->>'provider_uid' LIKE '%regtest%';
    DELETE FROM public.journal WHERE created_by = 'reg_test';
    DELETE FROM auth.user_identity WHERE uid LIKE '%regtest%';
    DELETE FROM auth.user_data WHERE user_id IN (SELECT user_id FROM auth.user_info WHERE username LIKE '%regtest%');
    DELETE FROM auth.user_info WHERE username LIKE '%regtest%';

    RAISE NOTICE 'CLEANUP: Done';
END $$;
