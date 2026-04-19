set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 007: Role assignment on a path cascades via role→flag mapping
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __result boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 007: Role on path ---';

    -- Assign fsitem_editor role on ancestor path (role includes read + write)
    PERFORM auth.assign_resource_role(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _role_codes     := ARRAY['fsitem_editor'],
        _resource_path  := 'roles_test.root'::ext.ltree
    );

    -- TEST 1: Role-derived read on descendant
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'roles_test.root.sub.leaf'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Role-derived read cascades to descendant';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected role-derived read';
    END IF;

    -- TEST 2: Role-derived write on descendant
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'write',
        _resource_path  := 'roles_test.root.sub.leaf'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Role-derived write cascades';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected role-derived write';
    END IF;

    -- TEST 3: Flag not in role → false
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'delete',
        _resource_path  := 'roles_test.root.sub.leaf'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Flag not in role correctly returns false';
    ELSE
        RAISE EXCEPTION 'FAIL: Flag not in role should return false';
    END IF;

    -- TEST 4: Revoke the role
    PERFORM auth.revoke_resource_role(
        _deleted_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _role_codes     := ARRAY['fsitem_editor'],
        _resource_path  := 'roles_test.root'::ext.ltree
    );

    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_path  := 'roles_test.root.sub.leaf'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Role revocation removes access';
    ELSE
        RAISE EXCEPTION 'FAIL: Role should be revoked';
    END IF;
END $$;
