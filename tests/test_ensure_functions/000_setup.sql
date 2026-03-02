set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Ensure Functions - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';

    -- Using system user (id=1) which bypasses all permission checks
    PERFORM set_config('test_ef.user_id', '1', false);
    PERFORM set_config('test_ef.correlation_id', 'test_ensure_functions', false);

    -- Create a test provider that allows group mapping (needed for mapping tests)
    INSERT INTO auth.provider (created_by, updated_by, code, name, is_active, allows_group_mapping)
    VALUES ('test_ef', 'test_ef', 'test_ef_prov', 'Test EF Provider', true, true)
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'SETUP: Using system user_id=1, correlation_id=test_ensure_functions, provider=test_ef_prov';
END $$;
