set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 003: Group grant via path + user deny overrides group grant
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;  -- member of editors group
    __group_1 integer;  -- editors
    __result boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;
    SELECT val FROM _rap_test_data WHERE key = 'group_id_1' INTO __group_1;

    RAISE NOTICE '--- Test 003: Group path grant + user deny override ---';

    -- Group grant at ancestor path
    PERFORM auth.assign_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _user_group_id   := __group_1,
        _access_flags    := ARRAY['read'],
        _resource_path   := 'shared.projects'::ext.ltree
    );

    -- TEST 1: Group member gets read via group grant on ancestor
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'shared.projects.alpha.doc_md'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Group member inherits read on descendant via group grant';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected group-path access';
    END IF;

    -- User-level deny on specific subtree
    PERFORM auth.deny_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _target_user_id  := __user_2,
        _access_flags    := ARRAY['read'],
        _resource_path   := 'shared.projects.alpha'::ext.ltree
    );

    -- TEST 2: User deny overrides group grant on matching subtree
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'shared.projects.alpha.doc_md'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: User deny beats group grant on subtree';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected user deny to win';
    END IF;

    -- TEST 3: User deny doesn't leak to sibling
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'shared.projects.beta.doc_md'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Sibling subtree retains group grant (deny scoped)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected sibling subtree retention';
    END IF;
END $$;
