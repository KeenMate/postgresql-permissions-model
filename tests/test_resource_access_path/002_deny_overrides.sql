set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 002: Deny on descendant path overrides ancestor grant
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __result boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 002: Deny overrides on descendant subtree ---';

    -- Setup: grant write at ancestor
    PERFORM auth.assign_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _target_user_id  := __user_2,
        _access_flags    := ARRAY['write'],
        _resource_path   := 'srv.data.org_123'::ext.ltree
    );

    -- TEST 1: Write cascades to descendant
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'srv.data.org_123.private.secret_txt'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Ancestor write cascades to private/secret.txt';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected write on descendant';
    END IF;

    -- Setup deny on descendant subtree
    PERFORM auth.deny_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _target_user_id  := __user_2,
        _access_flags    := ARRAY['write'],
        _resource_path   := 'srv.data.org_123.private'::ext.ltree
    );

    -- TEST 2: Deny on deeper path blocks write
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'srv.data.org_123.private.secret_txt'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Deny at srv.data.org_123.private blocks write on descendant';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected write denied by ancestor deny';
    END IF;

    -- TEST 3: Deny does not leak to sibling subtree
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'srv.data.org_123.public.notes_txt'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Sibling subtree still has write (deny scoped to private/)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected sibling to retain write';
    END IF;

    -- TEST 4: Deny does not leak to ancestor itself
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'srv.data.org_123'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Ancestor itself retains write (deny only scopes down)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected ancestor to retain write';
    END IF;
END $$;
