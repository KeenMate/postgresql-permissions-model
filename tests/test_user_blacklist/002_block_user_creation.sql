set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 5: unsecure.create_user_info raises 33018 for blacklisted username
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 5: unsecure.create_user_info raises 33018 for blacklisted username';

    BEGIN
        SELECT * INTO __result
        FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
            'blacklisted_user@test.com', 'blacklisted_user@test.com', 'Blacklisted User', null);

        RAISE EXCEPTION '  FAIL: Should have raised 33018 but user was created';
    EXCEPTION WHEN SQLSTATE '33018' THEN
        RAISE NOTICE '  PASS: create_user_info raised 33018 for blacklisted username';
    END;
END $$;

-- ============================================================================
-- TEST 6: auth.register_user blocked for blacklisted username
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 6: auth.register_user blocked for blacklisted username';

    BEGIN
        SELECT * INTO __result
        FROM auth.register_user('test_bl', 1, 'test_blacklist',
            'blacklisted_user@test.com', '$hash$test', 'Blacklisted User');

        RAISE EXCEPTION '  FAIL: Should have raised 33018 but user was registered';
    EXCEPTION WHEN SQLSTATE '33018' THEN
        RAISE NOTICE '  PASS: register_user raised 33018 for blacklisted username';
    END;
END $$;

-- ============================================================================
-- TEST 7: auth.ensure_user_info blocked for new blacklisted user
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 7: auth.ensure_user_info blocked for new blacklisted user';

    BEGIN
        SELECT * INTO __result
        FROM auth.ensure_user_info('test_bl', 1, 'test_blacklist',
            'blacklisted_user@test.com', 'Blacklisted User');

        RAISE EXCEPTION '  FAIL: Should have raised 33018 but user was ensured';
    EXCEPTION WHEN SQLSTATE '33018' THEN
        RAISE NOTICE '  PASS: ensure_user_info raised 33018 for blacklisted username';
    END;
END $$;

-- ============================================================================
-- TEST 8: auth.ensure_user_from_provider blocked by provider_uid
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 8: auth.ensure_user_from_provider blocked by provider_uid (even with different username)';

    BEGIN
        SELECT * INTO __result
        FROM auth.ensure_user_from_provider('test_bl', 1, 'test_blacklist',
            'test_bl_aad', 'blacklisted-aad-uid-001', 'some-oid',
            'completely_different_username@test.com', 'Different User');

        RAISE EXCEPTION '  FAIL: Should have raised 33019 but user was ensured from provider';
    EXCEPTION WHEN SQLSTATE '33019' THEN
        RAISE NOTICE '  PASS: ensure_user_from_provider raised 33019 for blacklisted provider_uid';
    END;
END $$;

-- ============================================================================
-- TEST 9: unsecure.create_user_identity raises 33019 for blacklisted provider_oid
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 9: unsecure.create_user_identity raises 33019 for blacklisted provider_oid (defense-in-depth)';

    -- create a clean user first
    SELECT user_id INTO __test_user_id
    FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
        'bl_identity_test_user@test.com', 'bl_identity_test@test.com', 'Identity Test User', null);

    BEGIN
        SELECT * INTO __result
        FROM unsecure.create_user_identity('test_bl', 1, 'test_blacklist',
            __test_user_id, 'test_bl_aad', 'some-new-uid', 'blacklisted-oid-001');

        RAISE EXCEPTION '  FAIL: Should have raised 33019 but identity was created';
    EXCEPTION WHEN SQLSTATE '33019' THEN
        RAISE NOTICE '  PASS: create_user_identity raised 33019 for blacklisted provider_oid';
    END;
END $$;
