set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- CLEANUP: Transaction rollback handles data cleanup, this is just a notice
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Audit Events & User Self-Service Ops Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 10 tests passed:';
    RAISE NOTICE '  1.  create_user_event stores an audit event';
    RAISE NOTICE '  2.  create_user_event stores request_context and event_data';
    RAISE NOTICE '  3.  get_user_audit_trail returns events for a target user';
    RAISE NOTICE '  4.  get_security_events returns security-related events';
    RAISE NOTICE '  5.  search_user_events filters by event_type_code';
    RAISE NOTICE '  6.  update_user_password changes password_hash';
    RAISE NOTICE '  7.  update_user_password self-update (no permission check)';
    RAISE NOTICE '  8.  update_user_preferences merges jsonb preferences';
    RAISE NOTICE '  9.  get_user_preferences returns stored preferences';
    RAISE NOTICE '  10. update_user_last_selected_tenant sets tenant';
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Transaction rollback will handle data cleanup';
END $$;
