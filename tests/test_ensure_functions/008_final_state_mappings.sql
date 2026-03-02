set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 42: _is_final_state=false (default) does NOT remove mappings
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __count_before   int;
    __count_after    int;
BEGIN
    RAISE NOTICE 'TEST 42: ensure_user_group_mappings - default does NOT remove mappings';

    -- Create an external group for mapping tests
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Mapping Group", "is_external": true}]'::jsonb,
        1,
        'fs_map_test'
    );

    SELECT user_group_id INTO __group_id
    FROM auth.user_group WHERE code = 'fs_mapping_group' AND tenant_id = 1;

    -- Create 2 mappings
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-001", "mapped_object_name": "AAD Group 1"},
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-002", "mapped_object_name": "AAD Group 2"}
        ]')::jsonb
    );

    SELECT count(*) INTO __count_before
    FROM auth.user_group_mapping WHERE user_group_id = __group_id AND provider_code = 'test_ef_prov';

    -- Call with only 1 mapping, _is_final_state defaults to false
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-001"}
        ]')::jsonb
    );

    SELECT count(*) INTO __count_after
    FROM auth.user_group_mapping WHERE user_group_id = __group_id AND provider_code = 'test_ef_prov';

    IF __count_before = __count_after AND __count_after = 2 THEN
        RAISE NOTICE '  PASS: Default mode did not remove mappings (before=%, after=%)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Default mode should not remove (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 43: _is_final_state=true removes unlisted mappings for same (group, provider)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __count          int;
    __has_001        boolean;
    __has_002        boolean;
BEGIN
    RAISE NOTICE 'TEST 43: ensure_user_group_mappings - final_state removes unlisted same-group mappings';

    SELECT user_group_id INTO __group_id
    FROM auth.user_group WHERE code = 'fs_mapping_group' AND tenant_id = 1;

    -- Call with only guid-001, final_state=true => guid-002 should be removed
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-001"}
        ]')::jsonb,
        1,
        true  -- _is_final_state
    );

    SELECT count(*) INTO __count
    FROM auth.user_group_mapping WHERE user_group_id = __group_id AND provider_code = 'test_ef_prov';

    SELECT
        exists(SELECT 1 FROM auth.user_group_mapping WHERE user_group_id = __group_id AND mapped_object_id = 'map-guid-001'),
        exists(SELECT 1 FROM auth.user_group_mapping WHERE user_group_id = __group_id AND mapped_object_id = 'map-guid-002')
    INTO __has_001, __has_002;

    IF __count = 1 AND __has_001 AND NOT __has_002 THEN
        RAISE NOTICE '  PASS: Final state removed guid-002 (count=%, has_001=%, has_002=%)', __count, __has_001, __has_002;
    ELSE
        RAISE EXCEPTION '  FAIL: Final state removal wrong (count=%, has_001=%, has_002=%)', __count, __has_001, __has_002;
    END IF;
END $$;

-- ============================================================================
-- TEST 44: _is_final_state=true scoped by (group, provider) - other combos untouched
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __other_group_id int;
    __other_count    int;
BEGIN
    RAISE NOTICE 'TEST 44: ensure_user_group_mappings - final_state scoped by (group, provider)';

    SELECT user_group_id INTO __group_id
    FROM auth.user_group WHERE code = 'fs_mapping_group' AND tenant_id = 1;

    -- Create another external group with its own mappings
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "FS Other Map Group", "is_external": true}]'::jsonb,
        1,
        'fs_map_test'
    );

    SELECT user_group_id INTO __other_group_id
    FROM auth.user_group WHERE code = 'fs_other_map_group' AND tenant_id = 1;

    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __other_group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "other-guid-001"},
            {"user_group_id": ' || __other_group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "other-guid-002"}
        ]')::jsonb
    );

    -- Run final_state for fs_mapping_group only - other group should be untouched
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-001"}
        ]')::jsonb,
        1,
        true
    );

    SELECT count(*) INTO __other_count
    FROM auth.user_group_mapping WHERE user_group_id = __other_group_id AND provider_code = 'test_ef_prov';

    IF __other_count = 2 THEN
        RAISE NOTICE '  PASS: Other group mappings untouched (count=%)', __other_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Other group mappings affected (count=%)', __other_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 45: _is_final_state=true with role-based mappings
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __count          int;
    __has_role_a     boolean;
    __has_role_b     boolean;
BEGIN
    RAISE NOTICE 'TEST 45: ensure_user_group_mappings - final_state with role-based mappings';

    SELECT user_group_id INTO __group_id
    FROM auth.user_group WHERE code = 'fs_mapping_group' AND tenant_id = 1;

    -- Add role-based mappings
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_role": "role_a"},
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_role": "role_b"}
        ]')::jsonb
    );

    -- Final state: keep only role_a and the existing guid-001, remove role_b
    PERFORM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "map-guid-001"},
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_role": "role_a"}
        ]')::jsonb,
        1,
        true
    );

    SELECT count(*) INTO __count
    FROM auth.user_group_mapping WHERE user_group_id = __group_id AND provider_code = 'test_ef_prov';

    SELECT
        exists(SELECT 1 FROM auth.user_group_mapping WHERE user_group_id = __group_id AND mapped_role = 'role_a'),
        exists(SELECT 1 FROM auth.user_group_mapping WHERE user_group_id = __group_id AND mapped_role = 'role_b')
    INTO __has_role_a, __has_role_b;

    IF __count = 2 AND __has_role_a AND NOT __has_role_b THEN
        RAISE NOTICE '  PASS: Role mappings synced (count=%, role_a=%, role_b=%)', __count, __has_role_a, __has_role_b;
    ELSE
        RAISE EXCEPTION '  FAIL: Role mapping sync failed (count=%, role_a=%, role_b=%)', __count, __has_role_a, __has_role_b;
    END IF;
END $$;
