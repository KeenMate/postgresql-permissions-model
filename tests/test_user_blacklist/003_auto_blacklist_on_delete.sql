set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: unsecure.delete_user_by_id with _blacklist := true
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __result record;
    __bl_count int;
BEGIN
    RAISE NOTICE 'TEST 10: Auto-blacklist on delete (_blacklist := true)';

    -- create user with identity
    SELECT user_id INTO __user_id
    FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
        'autoblacklist_user@test.com', 'autoblacklist@test.com', 'Auto Blacklist User', 'test_bl_aad');

    PERFORM unsecure.create_user_identity('test_bl', 1, 'test_blacklist',
        __user_id, 'test_bl_aad', 'auto-bl-aad-uid', 'auto-bl-aad-oid', _is_active := true);

    PERFORM set_config('test_bl.auto_bl_user_id', __user_id::text, false);

    -- delete with blacklist
    SELECT * INTO __result
    FROM unsecure.delete_user_by_id('test_bl', 1, 'test_blacklist', __user_id, true);

    IF __result.__user_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: User deleted, user_id=%', __result.__user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: User was not deleted';
    END IF;

    -- verify blacklist entries created (1 username + 1 identity = 2 entries)
    SELECT count(*) INTO __bl_count
    FROM auth.user_blacklist
    WHERE original_user_id = __user_id;

    IF __bl_count = 2 THEN
        RAISE NOTICE '  PASS: % blacklist entries created (username + provider identity)', __bl_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 blacklist entries, found %', __bl_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: Re-creation of auto-blacklisted user fails
-- ============================================================================
DO $$
DECLARE
    __result record;
BEGIN
    RAISE NOTICE 'TEST 11: Re-creation of auto-blacklisted user fails';

    -- try to re-create with same username
    BEGIN
        SELECT * INTO __result
        FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
            'autoblacklist_user@test.com', 'autoblacklist@test.com', 'Recreated User', null);

        RAISE EXCEPTION '  FAIL: Should have raised 33018 but user was re-created';
    EXCEPTION WHEN SQLSTATE '33018' THEN
        RAISE NOTICE '  PASS: Re-creation of username blocked';
    END;

    -- try to re-authenticate via provider
    BEGIN
        SELECT * INTO __result
        FROM auth.ensure_user_from_provider('test_bl', 1, 'test_blacklist',
            'test_bl_aad', 'auto-bl-aad-uid', 'auto-bl-aad-oid',
            'completely_new_email@test.com', 'New Display Name');

        RAISE EXCEPTION '  FAIL: Should have raised 33019 but user was ensured from provider';
    EXCEPTION WHEN SQLSTATE '33019' THEN
        RAISE NOTICE '  PASS: Re-authentication via provider blocked';
    END;
END $$;
