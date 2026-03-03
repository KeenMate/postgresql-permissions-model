set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 12: auth.remove_from_blacklist removes entry
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint := current_setting('test_bl.admin_user_id')::bigint;
    __corr_id text := current_setting('test_bl.correlation_id');
    __bl_id bigint := current_setting('test_bl.bl_username_id')::bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 12: auth.remove_from_blacklist removes entry';

    SELECT * INTO __result
    FROM auth.remove_from_blacklist('test_bl', __admin_id, __corr_id, __bl_id);

    IF __result.__removed_blacklist_id = __bl_id THEN
        RAISE NOTICE '  PASS: Blacklist entry % removed, username=%', __result.__removed_blacklist_id, __result.__username;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected removed blacklist_id=%, got %', __bl_id, __result.__removed_blacklist_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: Verify unblacklisted username can be used again
-- ============================================================================
DO $$
DECLARE
    __is_bl boolean;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 13: Verify unblacklisted username can be used again';

    -- confirm no longer blacklisted
    SELECT auth.is_blacklisted(_username := 'blacklisted_user@test.com') INTO __is_bl;
    IF NOT __is_bl THEN
        RAISE NOTICE '  PASS: Username is no longer blacklisted';
    ELSE
        RAISE EXCEPTION '  FAIL: Username should no longer be blacklisted';
    END IF;

    -- confirm user can be created
    SELECT * INTO __result
    FROM unsecure.create_user_info('test_bl', 1, 'test_blacklist',
        'blacklisted_user@test.com', 'blacklisted_user@test.com', 'Unblacklisted User', null);

    IF __result.user_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: User created successfully after unblacklist, user_id=%', __result.user_id;
    ELSE
        RAISE EXCEPTION '  FAIL: User could not be created after unblacklist';
    END IF;
END $$;
