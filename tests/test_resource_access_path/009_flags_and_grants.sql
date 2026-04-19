set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 009: get_resource_access_flags + get_resource_grants for path resources
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __flag_count integer;
    __grant_count integer;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 009: Flags and grants queries on paths ---';

    -- Grant multiple flags at ancestor
    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read', 'write'],
        _resource_path  := 'flags_test.root'::ext.ltree
    );

    -- TEST 1: get_resource_access_flags on descendant returns inherited flags
    SELECT COUNT(*) INTO __flag_count
    FROM auth.get_resource_access_flags(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _resource_path  := 'flags_test.root.sub.leaf'::ext.ltree
    );

    IF __flag_count >= 2 THEN
        RAISE NOTICE 'PASS: get_resource_access_flags returns inherited flags (count=%)', __flag_count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 2 flags, got %', __flag_count;
    END IF;

    -- TEST 2: get_resource_grants on exact path returns 2 rows (read + write)
    SELECT COUNT(*) INTO __grant_count
    FROM auth.get_resource_grants(
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _resource_path  := 'flags_test.root'::ext.ltree
    )
    WHERE __user_id = __user_2;

    IF __grant_count = 2 THEN
        RAISE NOTICE 'PASS: get_resource_grants returns both flags on exact path';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 2 grants on exact path, got %', __grant_count;
    END IF;

    -- TEST 3: get_resource_grants on descendant path returns 0 (exact match only)
    SELECT COUNT(*) INTO __grant_count
    FROM auth.get_resource_grants(
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _resource_path  := 'flags_test.root.sub'::ext.ltree
    )
    WHERE __user_id = __user_2;

    IF __grant_count = 0 THEN
        RAISE NOTICE 'PASS: get_resource_grants uses exact-path match (no walk)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 0 grants on descendant, got %', __grant_count;
    END IF;
END $$;
