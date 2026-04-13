set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 7: get_user_identity_by_email returns identity by email
-- ============================================================================
DO $$
DECLARE
    __result record;
    __corr_id text := 'idp-email-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 7: get_user_identity_by_email returns identity by email';

    SELECT * INTO __result
    FROM auth.get_user_identity_by_email(1, __corr_id, 'idp_test_user1@test.com', 'test_idp');

    IF __result.__user_identity_id IS NOT NULL
       AND __result.__provider_code = 'test_idp'
       AND __result.__uid = 'idp_test_uid_1' THEN
        RAISE NOTICE '  PASS: identity found by email (id=%, provider=%, uid=%)',
            __result.__user_identity_id, __result.__provider_code, __result.__uid;
    ELSE
        RAISE EXCEPTION '  FAIL: expected identity for idp_test_user1@test.com, got id=%, provider=%, uid=%',
            __result.__user_identity_id, __result.__provider_code, __result.__uid;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: get_user_by_id returns user data
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-byid-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 8: get_user_by_id returns user data';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT * INTO __result
    FROM auth.get_user_by_id(__target_user_id, __corr_id);

    IF __result.__user_id = __target_user_id
       AND __result.__username = 'idp_test_user1'
       AND __result.__email = 'idp_test_user1@test.com'
       AND __result.__display_name = 'IDP Test User 1' THEN
        RAISE NOTICE '  PASS: user returned (id=%, username=%, email=%)',
            __result.__user_id, __result.__username, __result.__email;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected user data (id=%, username=%, email=%, display_name=%)',
            __result.__user_id, __result.__username, __result.__email, __result.__display_name;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: get_user_by_provider_oid returns user by OID
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-byoid-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 9: get_user_by_provider_oid returns user by OID';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT * INTO __result
    FROM auth.get_user_by_provider_oid(1, __corr_id, 'idp_test_oid_1');

    IF __result.__user_id = __target_user_id
       AND __result.__username = 'idp_test_user1' THEN
        RAISE NOTICE '  PASS: user found by OID (id=%, username=%)', __result.__user_id, __result.__username;
    ELSE
        RAISE EXCEPTION '  FAIL: expected user_id=%, got id=%, username=%',
            __target_user_id, __result.__user_id, __result.__username;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: get_user_last_selected_tenant returns tenant after setting it
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __tenant_uuid text;
    __corr_id text := 'idp-tenant-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 10: get_user_last_selected_tenant returns last selected tenant';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    -- get tenant 1 uuid
    SELECT t.uuid::text INTO __tenant_uuid FROM auth.tenant t WHERE t.tenant_id = 1;

    -- set last_selected_tenant_id directly (avoid permission issues with update function)
    UPDATE auth.user_info SET last_selected_tenant_id = 1 WHERE user_id = __target_user_id;

    SELECT * INTO __result
    FROM auth.get_user_last_selected_tenant(1, __corr_id, __target_user_id);

    IF __result.__tenant_id = 1 THEN
        RAISE NOTICE '  PASS: last selected tenant returned (tenant_id=%, code=%)',
            __result.__tenant_id, __result.__tenant_code;
    ELSE
        RAISE EXCEPTION '  FAIL: expected tenant_id=1, got %', __result.__tenant_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: get_user_last_selected_tenant returns empty when not set
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-notenant-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 11: get_user_last_selected_tenant returns empty when not set';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    -- clear last_selected_tenant_id
    UPDATE auth.user_info SET last_selected_tenant_id = NULL WHERE user_id = __target_user_id;

    SELECT * INTO __result
    FROM auth.get_user_last_selected_tenant(1, __corr_id, __target_user_id);

    IF __result.__tenant_id IS NULL THEN
        RAISE NOTICE '  PASS: no tenant returned when last_selected_tenant_id is null';
    ELSE
        RAISE EXCEPTION '  FAIL: expected null, got tenant_id=%', __result.__tenant_id;
    END IF;
END $$;
