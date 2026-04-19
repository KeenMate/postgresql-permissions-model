set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 006: Revoke specific path + revoke-all cascade
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __result boolean;
    __count bigint;
    __deleted bigint;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 006: Revoke paths ---';

    -- Set up grants at two paths
    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'revoke_test.a'::ext.ltree
    );

    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'revoke_test.a.child'::ext.ltree
    );

    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'revoke_test.b'::ext.ltree
    );

    -- TEST 1: revoke specific path (not descendants)
    __deleted := auth.revoke_resource_access(
        _deleted_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'revoke_test.a'::ext.ltree
    );

    IF __deleted = 1 THEN
        RAISE NOTICE 'PASS: revoke_resource_access removed exactly 1 row';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 1 deletion, got %', __deleted;
    END IF;

    -- Verify: 'revoke_test.a.child' still exists (not touched by specific revoke)
    SELECT COUNT(*) INTO __count
    FROM auth.resource_access
    WHERE user_id = __user_2
      AND resource_path = 'revoke_test.a.child'::ext.ltree;

    IF __count = 1 THEN
        RAISE NOTICE 'PASS: Specific revoke did not cascade to descendants';
    ELSE
        RAISE EXCEPTION 'FAIL: Descendant row wrongly affected';
    END IF;

    -- TEST 2: revoke_all_resource_access with path cascades (uses <@)
    __deleted := auth.revoke_all_resource_access(
        _deleted_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _resource_path  := 'revoke_test'::ext.ltree
    );

    IF __deleted >= 2 THEN
        RAISE NOTICE 'PASS: revoke_all_resource_access cascades path (deleted %)', __deleted;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 2 deletions, got %', __deleted;
    END IF;

    -- Verify no rows remain for revoke_test.*
    SELECT COUNT(*) INTO __count
    FROM auth.resource_access
    WHERE resource_path <@ 'revoke_test'::ext.ltree;

    IF __count = 0 THEN
        RAISE NOTICE 'PASS: All revoke_test.* rows removed';
    ELSE
        RAISE EXCEPTION 'FAIL: % rows still present under revoke_test', __count;
    END IF;
END $$;
