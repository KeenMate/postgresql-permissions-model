set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 001: Grant on ancestor path — descendants inherit
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __result boolean;
    __count integer;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 001: Path-based grant inheritance ---';

    -- TEST 1: Grant read on ancestor path
    PERFORM auth.assign_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _target_user_id  := __user_2,
        _access_flags    := ARRAY['read'],
        _resource_path   := 'srv.data.org_123'::ext.ltree
    );

    SELECT COUNT(*) INTO __count
    FROM auth.resource_access
    WHERE user_id = __user_2
      AND resource_path = 'srv.data.org_123'::ext.ltree
      AND access_flag = 'read';

    IF __count = 1 THEN
        RAISE NOTICE 'PASS: Path grant row created';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 1 path grant row, got %', __count;
    END IF;

    -- TEST 2: Check on exact ancestor path
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'srv.data.org_123'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Access granted on exact path';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected access on exact path';
    END IF;

    -- TEST 3: Check on descendant path
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'srv.data.org_123.reports.q1.summary_pdf'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Access cascades to descendant path';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected access on descendant path';
    END IF;

    -- TEST 4: Check on child resource_type with descendant path
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem.file',
        _required_flag  := 'read',
        _resource_path  := 'srv.data.org_123.reports.q1.summary_pdf'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Access cascades via both type hierarchy AND path hierarchy';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected access on child type + descendant path';
    END IF;

    -- TEST 5: Wrong flag returns false
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'srv.data.org_123.reports'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Wrong flag correctly returns false';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected false for non-granted flag';
    END IF;

    -- TEST 6: Unrelated path returns false
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'srv.data.org_999'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Unrelated path returns false';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected false for unrelated path';
    END IF;
END $$;
