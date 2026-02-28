set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Search Functions Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test data for search
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __api_key_id integer;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create a test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test_search', 'test_search', 'normal', 'search_test_user', 'search_test_user', 'Search Test User', 'search_test@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Search Test User'
    RETURNING user_id INTO __test_user_id;

    -- Create an inbound API key for search testing
    INSERT INTO auth.api_key (created_by, updated_by, tenant_id, title, description, api_key, secret_hash, key_type)
    VALUES ('test_search', 'test_search', 1, 'Search Test API Key', 'API key for search tests', 'search_test_key_001', '\x1234', 'inbound')
    ON CONFLICT (api_key) DO NOTHING;

    -- Create an outbound API key for search testing
    INSERT INTO auth.api_key (created_by, updated_by, tenant_id, title, description, api_key, key_type, encrypted_secret, service_code, service_url)
    VALUES ('test_search', 'test_search', 1, 'Search Test Outbound Key', 'Outbound key for search tests', 'search_test_outbound_001', 'outbound', '\x5678', 'test_service', 'https://test.example.com')
    ON CONFLICT (api_key) DO NOTHING;

    -- Create a journal entry for search testing
    INSERT INTO public.journal (created_by, correlation_id, tenant_id, event_id, user_id, data_payload)
    SELECT 'test_search', 'search-test-corr', 1, ec.event_id, 1, '{"test": true}'::jsonb
    FROM const.event_code ec LIMIT 1;

    -- Create a user event for search testing
    INSERT INTO auth.user_event (created_by, correlation_id, event_type_code, requester_user_id, target_user_id)
    VALUES ('test_search', 'search-test-corr', 'user_logged_in', 1, __test_user_id);

    RAISE NOTICE 'SETUP: Test user_id=%, created API keys and journal entries', __test_user_id;
    RAISE NOTICE '';
END $$;
