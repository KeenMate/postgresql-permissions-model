set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 005: Composite-key resources still work unchanged when path support is added
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __result boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 005: Composite-key coexistence ---';

    -- Composite-key grant (no path)
    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'proj',
        _resource_id    := '{"project_id": 42}'::jsonb,
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read']
    );

    -- TEST 1: Composite-key check still works
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'proj',
        _resource_id    := '{"project_id": 42}'::jsonb,
        _required_flag  := 'read',
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Composite-key grant and check work';
    ELSE
        RAISE EXCEPTION 'FAIL: Composite-key check failed';
    END IF;

    -- TEST 2: Different composite id returns false
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'proj',
        _resource_id    := '{"project_id": 99}'::jsonb,
        _required_flag  := 'read',
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Different composite id returns false';
    ELSE
        RAISE EXCEPTION 'FAIL: Wrong composite matched';
    END IF;

    -- TEST 3: Path grant and composite grant can coexist for same user on different types
    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'coexist.root'::ext.ltree
    );

    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'coexist.root.child'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Path grant works alongside composite grant';
    ELSE
        RAISE EXCEPTION 'FAIL: Path grant blocked by coexistence';
    END IF;

    -- TEST 4: Path-only check on composite type does NOT match composite grant
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'proj',
        _required_flag  := 'read',
        _resource_path  := 'some.arbitrary.path'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Path-only check on composite type correctly returns false';
    ELSE
        RAISE EXCEPTION 'FAIL: Path should not match composite-only grant';
    END IF;
END $$;
