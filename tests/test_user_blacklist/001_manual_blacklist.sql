set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: auth.add_to_blacklist for username
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 1: auth.add_to_blacklist for username';

    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _username := 'blacklisted_user@test.com',
        _reason := 'manual',
        _notes := 'Test blacklist entry');

    IF __result.__blacklist_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Blacklist entry created with id=%', __result.__blacklist_id;
        PERFORM set_config('test_bl.bl_username_id', __result.__blacklist_id::text, false);
    ELSE
        RAISE EXCEPTION '  FAIL: No blacklist entry created';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: auth.add_to_blacklist for provider identity (uid)
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 2: auth.add_to_blacklist for provider identity (uid)';

    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _provider_code := 'test_bl_aad',
        _provider_uid := 'blacklisted-aad-uid-001',
        _reason := 'policy_violation',
        _notes := 'Violated access policy');

    IF __result.__blacklist_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Provider uid blacklist entry created with id=%', __result.__blacklist_id;
        PERFORM set_config('test_bl.bl_provider_uid_id', __result.__blacklist_id::text, false);
    ELSE
        RAISE EXCEPTION '  FAIL: No blacklist entry created for provider uid';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: auth.add_to_blacklist for provider oid
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __result record;
BEGIN
    RAISE NOTICE 'TEST 3: auth.add_to_blacklist for provider oid';

    SELECT * INTO __result
    FROM auth.add_to_blacklist('test_bl', __admin_id, __corr_id,
        _provider_code := 'test_bl_aad',
        _provider_oid := 'blacklisted-oid-001',
        _reason := 'security_incident');

    IF __result.__blacklist_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Provider oid blacklist entry created with id=%', __result.__blacklist_id;
        PERFORM set_config('test_bl.bl_provider_oid_id', __result.__blacklist_id::text, false);
    ELSE
        RAISE EXCEPTION '  FAIL: No blacklist entry created for provider oid';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Verify entries exist via auth.is_blacklisted
-- ============================================================================
DO $$
DECLARE
    __is_bl boolean;
BEGIN
    RAISE NOTICE 'TEST 4: Verify entries exist via auth.is_blacklisted';

    -- check username
    SELECT auth.is_blacklisted(_username := 'blacklisted_user@test.com') INTO __is_bl;
    IF __is_bl THEN
        RAISE NOTICE '  PASS: Username is blacklisted';
    ELSE
        RAISE EXCEPTION '  FAIL: Username should be blacklisted';
    END IF;

    -- check provider uid
    SELECT auth.is_blacklisted(_provider_code := 'test_bl_aad', _provider_uid := 'blacklisted-aad-uid-001') INTO __is_bl;
    IF __is_bl THEN
        RAISE NOTICE '  PASS: Provider uid is blacklisted';
    ELSE
        RAISE EXCEPTION '  FAIL: Provider uid should be blacklisted';
    END IF;

    -- check provider oid
    SELECT auth.is_blacklisted(_provider_oid := 'blacklisted-oid-001') INTO __is_bl;
    IF __is_bl THEN
        RAISE NOTICE '  PASS: Provider oid is blacklisted';
    ELSE
        RAISE EXCEPTION '  FAIL: Provider oid should be blacklisted';
    END IF;

    -- check non-blacklisted
    SELECT auth.is_blacklisted(_username := 'not_blacklisted@test.com') INTO __is_bl;
    IF NOT __is_bl THEN
        RAISE NOTICE '  PASS: Non-blacklisted username returns false';
    ELSE
        RAISE EXCEPTION '  FAIL: Non-blacklisted username should return false';
    END IF;
END $$;
