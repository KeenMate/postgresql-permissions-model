set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Cache populated on first access
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __group_ids integer[];
    __cache_count integer;
BEGIN
    RAISE NOTICE 'TEST 1: Cache populated on first access';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Clear any existing cache for this user
    PERFORM unsecure.clear_user_group_id_cache(__user_id_2, null);

    -- Verify cache is empty
    SELECT count(*) FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __cache_count;

    IF __cache_count <> 0 THEN
        RAISE EXCEPTION '  FAIL: Cache should be empty before first access, got %', __cache_count;
    END IF;

    -- Call get_cached_group_ids — should populate cache
    __group_ids := unsecure.get_cached_group_ids(__user_id_2, 1);

    -- Verify cache row was created
    SELECT count(*) FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __cache_count;

    IF __cache_count = 1 AND array_length(__group_ids, 1) > 0 THEN
        RAISE NOTICE '  PASS: Cache populated with % group IDs', array_length(__group_ids, 1);
    ELSE
        RAISE EXCEPTION '  FAIL: Cache not populated correctly (count=%, groups=%)', __cache_count, __group_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Cache hit on second access
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __group_ids_1 integer[];
    __group_ids_2 integer[];
    __cached_expiration timestamptz;
    __expiration_after timestamptz;
BEGIN
    RAISE NOTICE 'TEST 2: Cache hit on second access';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Get the current cache expiration
    SELECT expiration_date FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __cached_expiration;

    -- Call again — should return same data without updating expiration
    __group_ids_1 := unsecure.get_cached_group_ids(__user_id_2, 1);

    SELECT expiration_date FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __expiration_after;

    IF __cached_expiration = __expiration_after THEN
        RAISE NOTICE '  PASS: Cache hit - expiration unchanged (same data returned)';
    ELSE
        RAISE EXCEPTION '  FAIL: Cache was unexpectedly refreshed (exp before=%, after=%)',
            __cached_expiration, __expiration_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Soft invalidation on group member change
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __group_id_2 integer;
    __exp_before timestamptz;
    __exp_after timestamptz;
    __group_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 3: Soft invalidation on group member change';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val::integer FROM _ra_test_data WHERE key = 'group_id_2' INTO __group_id_2;

    -- Get current cache expiration
    SELECT expiration_date FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __exp_before;

    -- Add user_2 to another group (triggers cache invalidation via trigger)
    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('test', __group_id_2, __user_id_2, 'manual');

    -- Cache should be invalidated (expiration_date <= now)
    SELECT expiration_date FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2 AND tenant_id = 1
    INTO __exp_after;

    IF __exp_after <= now() THEN
        RAISE NOTICE '  PASS: Cache invalidated after group member add (exp=%)', __exp_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Cache NOT invalidated after group member add (exp_before=%, exp_after=%)',
            __exp_before, __exp_after;
    END IF;

    -- Next access should rebuild cache with the new group
    __group_ids := unsecure.get_cached_group_ids(__user_id_2, 1);

    IF array_length(__group_ids, 1) >= 2 THEN
        RAISE NOTICE '  PASS: Cache rebuilt with % group IDs (includes new group)', array_length(__group_ids, 1);
    ELSE
        RAISE EXCEPTION '  FAIL: Cache rebuild expected >= 2 groups, got %', __group_ids;
    END IF;

    -- Clean up: remove user_2 from group_2
    DELETE FROM auth.user_group_member
    WHERE user_group_id = __group_id_2 AND user_id = __user_id_2 AND created_by = 'test';
END $$;

-- ============================================================================
-- TEST 4: Hard invalidation on user disable
-- ============================================================================
DO $$
DECLARE
    __user_id_2 bigint;
    __cache_count integer;
    __group_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 4: Hard invalidation on user disable';

    SELECT val FROM _ra_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    -- Ensure cache is populated
    __group_ids := unsecure.get_cached_group_ids(__user_id_2, 1);

    SELECT count(*) FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2
    INTO __cache_count;

    IF __cache_count = 0 THEN
        RAISE EXCEPTION '  FAIL: Cache should be populated before disable test';
    END IF;

    -- Disable user (triggers hard-clear of group ID cache)
    UPDATE auth.user_info SET is_active = false, updated_by = 'test' WHERE user_id = __user_id_2;

    SELECT count(*) FROM auth.user_group_id_cache
    WHERE user_id = __user_id_2
    INTO __cache_count;

    IF __cache_count = 0 THEN
        RAISE NOTICE '  PASS: Cache hard-cleared on user disable';
    ELSE
        RAISE EXCEPTION '  FAIL: Cache NOT cleared on user disable (count=%)', __cache_count;
    END IF;

    -- Re-enable user for subsequent tests
    UPDATE auth.user_info SET is_active = true, updated_by = 'test' WHERE user_id = __user_id_2;
END $$;
