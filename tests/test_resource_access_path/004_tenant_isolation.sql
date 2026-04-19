set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 004: Tenant isolation — path grants are scoped per tenant
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __tenant_2 integer;
    __result boolean;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;
    SELECT val::integer FROM _rap_test_data WHERE key = 'tenant_id_2' INTO __tenant_2;

    RAISE NOTICE '--- Test 004: Tenant isolation ---';

    -- Grant user_2 in tenant 1 on shared.tenant1_only
    PERFORM auth.assign_resource_access(
        _created_by      := 'test',
        _user_id         := __user_1,
        _correlation_id  := null,
        _resource_type   := 'fsitem',
        _target_user_id  := __user_2,
        _access_flags    := ARRAY['read'],
        _tenant_id       := 1,
        _resource_path   := 'shared.tenant1_only'::ext.ltree
    );

    -- TEST 1: Grant visible in tenant 1
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _tenant_id      := 1,
        _resource_path  := 'shared.tenant1_only.file_txt'::ext.ltree,
        _throw_err      := false
    );

    IF __result THEN
        RAISE NOTICE 'PASS: Grant visible in tenant 1';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected access in tenant 1';
    END IF;

    -- TEST 2: Grant NOT visible in tenant 2 (no bleed-through)
    __result := auth.has_resource_access(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _tenant_id      := __tenant_2,
        _resource_path  := 'shared.tenant1_only.file_txt'::ext.ltree,
        _throw_err      := false
    );

    IF NOT __result THEN
        RAISE NOTICE 'PASS: Tenant 2 does not see tenant 1 grants';
    ELSE
        RAISE EXCEPTION 'FAIL: Cross-tenant bleed';
    END IF;
END $$;
