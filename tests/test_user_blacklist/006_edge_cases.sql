set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 18: Blacklist same identity twice (should not error - creates duplicate entry)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 18: Blacklist same identity twice (creates separate entries)';

    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _provider_code := 'test_bl_aad',
        _provider_uid := 'blacklisted-aad-uid-001',
        _reason := 'duplicate_test');

    IF __result.__blacklist_id IS NOT NULL THEN
        -- count entries for this provider_uid
        SELECT count(*) INTO __count
        FROM auth.user_blacklist
        WHERE provider_uid = 'blacklisted-aad-uid-001';

        IF __count >= 2 THEN
            RAISE NOTICE '  PASS: Multiple blacklist entries allowed for same identity (count=%)', __count;
        ELSE
            RAISE EXCEPTION '  FAIL: Expected at least 2 entries, found %', __count;
        END IF;
    ELSE
        RAISE EXCEPTION '  FAIL: Second blacklist entry was not created';
    END IF;
END $$;

-- ============================================================================
-- TEST 19: Service user creation blocked by blacklist
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 19: Service user creation blocked by blacklist';

    -- first blacklist a service user name
    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _username := 'svc_blacklisted_service',
        _reason := 'manual');

    -- try to create service user with that name
    BEGIN
        SELECT * INTO __result
        FROM unsecure.create_service_user_info('test_bl', 1, 'test_blacklist',
            'svc_blacklisted_service', 'Blacklisted Service');

        RAISE EXCEPTION '  FAIL: Should have raised 33018 but service user was created';
    EXCEPTION WHEN SQLSTATE '33018' THEN
        RAISE NOTICE '  PASS: Service user creation blocked for blacklisted username';
    END;
END $$;

-- ============================================================================
-- TEST 20: Default _blacklist=false does NOT blacklist on delete
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __result record;
    __bl_count int;
BEGIN
    RAISE NOTICE 'TEST 20: Default _blacklist=false does NOT blacklist on delete';

    -- create a user
    SELECT user_id INTO __user_id
    FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
        'no_blacklist_on_delete@test.com', 'no_bl@test.com', 'No Blacklist User', null);

    -- delete WITHOUT blacklist (default)
    SELECT * INTO __result
    FROM unsecure.delete_user_by_id('test_bl', 1, 'test_blacklist', __user_id);

    IF __result.__user_id IS NOT NULL THEN
        RAISE NOTICE '  User deleted, user_id=%', __result.__user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: User was not deleted';
    END IF;

    -- verify no blacklist entries
    SELECT count(*) INTO __bl_count
    FROM auth.user_blacklist
    WHERE original_user_id = __user_id;

    IF __bl_count = 0 THEN
        RAISE NOTICE '  PASS: No blacklist entries created with default _blacklist=false';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 blacklist entries, found %', __bl_count;
    END IF;

    -- verify user can be re-created
    SELECT user_id INTO __user_id
    FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
        'no_blacklist_on_delete@test.com', 'no_bl@test.com', 'Recreated User', null);

    IF __user_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: User re-created successfully (no blacklist), user_id=%', __user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: User could not be re-created';
    END IF;
END $$;

-- ============================================================================
-- TEST 21: Case-insensitive username blacklist matching
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
    __is_bl boolean;
BEGIN
    RAISE NOTICE 'TEST 21: Case-insensitive username blacklist matching';

    -- blacklist lowercase
    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _username := 'CaseTest@Test.COM',
        _reason := 'case_test');

    -- check with different case
    SELECT auth.is_blacklisted(_username := 'casetest@test.com') INTO __is_bl;
    IF __is_bl THEN
        RAISE NOTICE '  PASS: Lowercase match works';
    ELSE
        RAISE EXCEPTION '  FAIL: Lowercase match should work';
    END IF;

    SELECT auth.is_blacklisted(_username := 'CASETEST@TEST.COM') INTO __is_bl;
    IF __is_bl THEN
        RAISE NOTICE '  PASS: Uppercase match works';
    ELSE
        RAISE EXCEPTION '  FAIL: Uppercase match should work';
    END IF;
END $$;
