set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: get_provider_users returns users linked to a provider
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __result_count int;
    __result_user_id bigint;
BEGIN
    RAISE NOTICE 'TEST 10: get_provider_users returns linked users';

    -- Create a test user identity linked to prov_test_1
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('prov_test', 'prov_test', 'normal', 'prov_test_user_1', 'prov_test_user_1', 'Prov Test User', 'prov_test@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Prov Test User'
    RETURNING user_id INTO __test_user_id;

    INSERT INTO auth.user_identity (created_by, updated_by, provider_code, user_id, provider_oid, uid)
    VALUES ('prov_test', 'prov_test', 'prov_test_1', __test_user_id, 'prov_test_oid_1', 'prov_test_uid_1')
    ON CONFLICT (provider_oid) DO NOTHING;

    SELECT count(*), min(gpu.__user_id)
    FROM auth.get_provider_users('prov_test', 1, 'prov-test-gpu', 'prov_test_1') gpu
    INTO __result_count, __result_user_id;

    IF __result_count >= 1 AND __result_user_id = __test_user_id THEN
        RAISE NOTICE '  PASS: get_provider_users returned % user(s), including user_id=%', __result_count, __result_user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected >=1 user with user_id=%, got count=%, user_id=%',
            __test_user_id, __result_count, __result_user_id;
    END IF;
END $$;
