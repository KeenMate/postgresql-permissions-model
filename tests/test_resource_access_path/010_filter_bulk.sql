set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 010: Bulk filter_accessible_resources with paths
-- ============================================================================
DO $$
DECLARE
    __user_1 bigint;
    __user_2 bigint;
    __accessible_count integer;
BEGIN
    SELECT val FROM _rap_test_data WHERE key = 'user_id_1' INTO __user_1;
    SELECT val FROM _rap_test_data WHERE key = 'user_id_2' INTO __user_2;

    RAISE NOTICE '--- Test 010: filter_accessible_resources with paths ---';

    -- Grant on a subtree
    PERFORM auth.assign_resource_access(
        _created_by     := 'test',
        _user_id        := __user_1,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := __user_2,
        _access_flags   := ARRAY['read'],
        _resource_path  := 'bulk_test.allowed'::ext.ltree
    );

    -- Filter a list of candidate paths
    SELECT COUNT(*) INTO __accessible_count
    FROM auth.filter_accessible_resources(
        _user_id        := __user_2,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _required_flag  := 'read',
        _resource_paths := ARRAY[
            'bulk_test.allowed.a'::ext.ltree,
            'bulk_test.allowed.b.c'::ext.ltree,
            'bulk_test.forbidden.x'::ext.ltree,
            'bulk_test.forbidden.y'::ext.ltree
        ]
    );

    IF __accessible_count = 2 THEN
        RAISE NOTICE 'PASS: filter_accessible_resources returns only covered paths (2)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 2 accessible paths, got %', __accessible_count;
    END IF;
END $$;
