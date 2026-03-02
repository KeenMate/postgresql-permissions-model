set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 21: Create mappings using user_group_id
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __returned       int;
BEGIN
    RAISE NOTICE 'TEST 21: ensure_user_group_mappings - create using user_group_id';

    -- Need an external group for mappings
    PERFORM auth.ensure_user_groups(
        'test_ef', __user_id, __correlation_id,
        '[{"title": "Test Mapped Group", "is_external": true}]'::jsonb
    );

    SELECT ug.user_group_id
    FROM auth.user_group ug
    WHERE ug.code = 'test_mapped_group' AND ug.tenant_id = 1
    INTO __group_id;

    SELECT count(*) INTO __returned
    FROM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-001", "mapped_object_name": "AAD Test Group 1"}
        ]')::jsonb
    );

    IF __returned = 1 THEN
        RAISE NOTICE '  PASS: Created mapping by user_group_id (returned=%, group_id=%)', __returned, __group_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Mapping creation failed (returned=%, group_id=%)', __returned, __group_id;
    END IF;
END $$;

-- ============================================================================
-- TEST 22: Create mappings using user_group_title (convenience)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __returned       int;
    __mapping_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 22: ensure_user_group_mappings - create using user_group_title';

    SELECT count(*) INTO __returned
    FROM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        '[
            {"user_group_title": "Test Mapped Group", "provider_code": "test_ef_prov", "mapped_role": "test_admin_role"}
        ]'::jsonb
    );

    SELECT exists(
        SELECT 1 FROM auth.user_group_mapping ugm
        INNER JOIN auth.user_group ug ON ugm.user_group_id = ug.user_group_id
        WHERE ug.code = 'test_mapped_group'
          AND ugm.provider_code = 'test_ef_prov'
          AND ugm.mapped_role = 'test_admin_role'
    ) INTO __mapping_exists;

    IF __returned = 1 AND __mapping_exists THEN
        RAISE NOTICE '  PASS: Created mapping by user_group_title (returned=%, exists=%)', __returned, __mapping_exists;
    ELSE
        RAISE EXCEPTION '  FAIL: Title-based mapping failed (returned=%, exists=%)', __returned, __mapping_exists;
    END IF;
END $$;

-- ============================================================================
-- TEST 23: ensure_user_group_mappings is idempotent
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __count_before   int;
    __count_after    int;
    __returned       int;
BEGIN
    RAISE NOTICE 'TEST 23: ensure_user_group_mappings - idempotent (no duplicates)';

    SELECT ug.user_group_id
    FROM auth.user_group ug
    WHERE ug.code = 'test_mapped_group' AND ug.tenant_id = 1
    INTO __group_id;

    SELECT count(*) INTO __count_before
    FROM auth.user_group_mapping
    WHERE user_group_id = __group_id;

    SELECT count(*) INTO __returned
    FROM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-001", "mapped_object_name": "AAD Test Group 1"},
            {"user_group_title": "Test Mapped Group", "provider_code": "test_ef_prov", "mapped_role": "test_admin_role"}
        ]')::jsonb
    );

    SELECT count(*) INTO __count_after
    FROM auth.user_group_mapping
    WHERE user_group_id = __group_id;

    IF __count_before = __count_after AND __returned = 2 THEN
        RAISE NOTICE '  PASS: Idempotent (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    ELSE
        RAISE EXCEPTION '  FAIL: Not idempotent (before=%, after=%, returned=%)', __count_before, __count_after, __returned;
    END IF;
END $$;

-- ============================================================================
-- TEST 24: Multiple mappings in one call (mix of id and title)
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __returned       int;
    __total_mappings int;
BEGIN
    RAISE NOTICE 'TEST 24: ensure_user_group_mappings - multiple mappings (mix id + title)';

    SELECT ug.user_group_id
    FROM auth.user_group ug
    WHERE ug.code = 'test_mapped_group' AND ug.tenant_id = 1
    INTO __group_id;

    SELECT count(*) INTO __returned
    FROM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-001"},
            {"user_group_title": "Test Mapped Group", "provider_code": "test_ef_prov", "mapped_role": "test_admin_role"},
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-002", "mapped_object_name": "AAD Test Group 2"}
        ]')::jsonb
    );

    SELECT count(*)
    FROM auth.user_group_mapping
    WHERE user_group_id = __group_id
    INTO __total_mappings;

    -- 2 existing (guid-001, admin_role) + 1 new (guid-002) = 3 total, returned should be 3
    IF __returned = 3 AND __total_mappings = 3 THEN
        RAISE NOTICE '  PASS: Multiple mappings (returned=%, total=%)', __returned, __total_mappings;
    ELSE
        RAISE EXCEPTION '  FAIL: Multiple mappings failed (returned=%, total=%)', __returned, __total_mappings;
    END IF;
END $$;

-- ============================================================================
-- TEST 25: Invalid user_group_title raises error
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
BEGIN
    RAISE NOTICE 'TEST 25: ensure_user_group_mappings - invalid title raises error';

    BEGIN
        PERFORM auth.ensure_user_group_mappings(
            'test_ef', __user_id, __correlation_id,
            '[
                {"user_group_title": "Nonexistent Group ZZZZZ", "provider_code": "test_ef_prov", "mapped_role": "some_role"}
            ]'::jsonb
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown for invalid group title';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%52171%' OR SQLSTATE != '00000' THEN
                RAISE NOTICE '  PASS: Correctly raised error for invalid group title (sqlstate=%, sqlerrm=%)', SQLSTATE, SQLERRM;
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 26: Mappings returned in order by user_group_mapping_id
-- ============================================================================
DO $$
DECLARE
    __user_id        bigint := current_setting('test_ef.user_id')::bigint;
    __correlation_id text   := current_setting('test_ef.correlation_id');
    __group_id       int;
    __first_id       int;
    __last_id        int;
BEGIN
    RAISE NOTICE 'TEST 26: ensure_user_group_mappings - returned ordered by mapping_id';

    SELECT ug.user_group_id
    FROM auth.user_group ug
    WHERE ug.code = 'test_mapped_group' AND ug.tenant_id = 1
    INTO __group_id;

    SELECT min(user_group_mapping_id), max(user_group_mapping_id)
    FROM auth.ensure_user_group_mappings(
        'test_ef', __user_id, __correlation_id,
        ('[
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-001"},
            {"user_group_id": ' || __group_id || ', "provider_code": "test_ef_prov", "mapped_object_id": "test-guid-002"}
        ]')::jsonb
    )
    INTO __first_id, __last_id;

    IF __first_id < __last_id THEN
        RAISE NOTICE '  PASS: Results ordered by mapping_id (first=%, last=%)', __first_id, __last_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Results not ordered (first=%, last=%)', __first_id, __last_id;
    END IF;
END $$;
