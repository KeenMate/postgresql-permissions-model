set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Create test data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __system_user_id bigint := 1;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Correlation ID Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';

    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email, is_active)
    VALUES ('corr_test', 'corr_test', 'normal', 'corr_test_user', 'corr_test_user', 'Correlation Test User', 'corr_test@test.com', true)
    ON CONFLICT (username) DO UPDATE SET display_name = 'Correlation Test User'
    RETURNING user_id INTO __test_user_id;

    -- Store test user id for subsequent tests
    PERFORM set_config('test.corr_user_id', __test_user_id::text, false);

    RAISE NOTICE 'SETUP: Test user_id=%', __test_user_id;
    RAISE NOTICE '';
END $$;
