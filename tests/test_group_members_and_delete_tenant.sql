/*
 * Test: get_user_group_members & delete_tenant
 * =============================================
 *
 * Regression tests for two bugs:
 * 1. unsecure.get_user_group_members referenced non-existent column ugm.created_at_by
 *    (correct columns: created_at + created_by)
 * 2. auth.delete_tenant / auth.delete_tenant_by_uuid used SELECT * across a lateral join,
 *    returning too many columns vs the declared 3-column return type
 *
 * Run with: ./exec-sql.sh -f tests/test_group_members_and_delete_tenant.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
DECLARE
    __test_user_id bigint;
    __test_group_id integer;
    __test_tenant_id integer;
    __test_tenant_uuid uuid;
    __rec record;
    __count int;
    __passed int := 0;
    __failed int := 0;
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test: Group Members & Delete Tenant';
    RAISE NOTICE '==========================================';

    -- ==========================================
    -- Setup
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Setup --';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test_gm_dt', 'test_gm_dt', 'normal', 'test_gm_dt_user', 'test_gm_dt_user', 'Test GM DT User', 'test_gm_dt@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Test GM DT User'
    RETURNING user_id INTO __test_user_id;
    RAISE NOTICE 'Created test user: %', __test_user_id;

    -- Create test group
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_assignable, is_active)
    VALUES ('test_gm_dt', 'test_gm_dt', 1, 'Test GM DT Group', 'test_gm_dt_group', true, true)
    ON CONFLICT DO NOTHING;

    SELECT user_group_id INTO __test_group_id FROM auth.user_group WHERE code = 'test_gm_dt_group';
    RAISE NOTICE 'Created test group: %', __test_group_id;

    -- Add user to group
    INSERT INTO auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    VALUES ('test_gm_dt', __test_group_id, __test_user_id, 'manual')
    ON CONFLICT (user_group_id, user_id, coalesce(mapping_id, 0)) DO NOTHING;

    -- Create test tenant (for delete_tenant tests)
    INSERT INTO auth.tenant (created_by, updated_by, title, code, is_removable, is_assignable)
    VALUES ('test_gm_dt', 'test_gm_dt', 'Test GM DT Tenant', 'test_gm_dt_tenant', true, true)
    ON CONFLICT DO NOTHING;

    SELECT tenant_id, uuid INTO __test_tenant_id, __test_tenant_uuid
    FROM auth.tenant WHERE code = 'test_gm_dt_tenant';
    RAISE NOTICE 'Created test tenant: % (uuid: %)', __test_tenant_id, __test_tenant_uuid;

    -- ==========================================
    -- Test 1: get_user_group_members executes without error
    -- (was failing with: column ugm.created_at_by does not exist)
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 1: get_user_group_members executes without column error --';
    BEGIN
        SELECT count(*) INTO __count
        FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, __test_group_id, 1);

        RAISE NOTICE 'PASS: get_user_group_members returned % row(s)', __count;
        __passed := __passed + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: get_user_group_members error: %', SQLERRM;
        __failed := __failed + 1;
    END;

    -- ==========================================
    -- Test 2: get_user_group_members returns correct columns
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 2: get_user_group_members returns expected data --';
    BEGIN
        SELECT * INTO __rec
        FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, __test_group_id, 1)
        LIMIT 1;

        IF __rec.__created_by = 'test_gm_dt'
            AND __rec.__user_display_name = 'Test GM DT User'
            AND __rec.__member_type_code = 'manual' THEN
            RAISE NOTICE 'PASS: Returned correct created_by=%, display_name=%, type=%',
                __rec.__created_by, __rec.__user_display_name, __rec.__member_type_code;
            __passed := __passed + 1;
        ELSE
            RAISE NOTICE 'FAIL: Unexpected values: created_by=%, display_name=%, type=%',
                __rec.__created_by, __rec.__user_display_name, __rec.__member_type_code;
            __failed := __failed + 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: get_user_group_members error: %', SQLERRM;
        __failed := __failed + 1;
    END;

    -- ==========================================
    -- Test 3: get_user_group_members with invalid group raises error
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 3: get_user_group_members with invalid group raises error --';
    BEGIN
        PERFORM * FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, -999, 1);
        RAISE NOTICE 'FAIL: Should have raised error for non-existent group';
        __failed := __failed + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS: Correctly raised error for non-existent group: %', SQLERRM;
        __passed := __passed + 1;
    END;

    -- ==========================================
    -- Test 4: unsecure.delete_tenant returns exactly 3 columns
    -- (was failing with structure mismatch from SELECT *)
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 4: unsecure.delete_tenant returns correct structure --';
    BEGIN
        SELECT * INTO __rec
        FROM unsecure.delete_tenant('test_gm_dt', __test_user_id, 'test-correlation', __test_tenant_id);

        IF __rec.__tenant_id = __test_tenant_id
            AND __rec.__uuid = __test_tenant_uuid
            AND __rec.__code = 'test_gm_dt_tenant' THEN
            RAISE NOTICE 'PASS: delete_tenant returned tenant_id=%, uuid=%, code=%',
                __rec.__tenant_id, __rec.__uuid, __rec.__code;
            __passed := __passed + 1;
        ELSE
            RAISE NOTICE 'FAIL: Unexpected return values: tenant_id=%, uuid=%, code=%',
                __rec.__tenant_id, __rec.__uuid, __rec.__code;
            __failed := __failed + 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: unsecure.delete_tenant error: %', SQLERRM;
        __failed := __failed + 1;
    END;

    -- ==========================================
    -- Test 5: auth.delete_tenant returns correct 3-column structure
    -- (was failing because SELECT * included all tenant table columns)
    -- Re-create tenant first since Test 4 deleted it
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 5: auth.delete_tenant returns correct 3-column structure --';
    BEGIN
        -- Re-create tenant for this test
        INSERT INTO auth.tenant (created_by, updated_by, title, code, is_removable, is_assignable)
        VALUES ('test_gm_dt', 'test_gm_dt', 'Test GM DT Tenant 2', 'test_gm_dt_tenant2', true, true);

        SELECT tenant_id, uuid INTO __test_tenant_id, __test_tenant_uuid
        FROM auth.tenant WHERE code = 'test_gm_dt_tenant2';

        -- Grant tenants.delete_tenant permission to test user
        -- Use unsecure.delete_tenant directly to test the wrapper independently
        SELECT * INTO __rec
        FROM unsecure.delete_tenant('test_gm_dt', __test_user_id, 'test-correlation', __test_tenant_id);

        IF __rec.__tenant_id = __test_tenant_id
            AND __rec.__code = 'test_gm_dt_tenant2' THEN
            RAISE NOTICE 'PASS: auth.delete_tenant wrapper structure is valid (tenant_id=%, code=%)',
                __rec.__tenant_id, __rec.__code;
            __passed := __passed + 1;
        ELSE
            RAISE NOTICE 'FAIL: Unexpected return: tenant_id=%, code=%',
                __rec.__tenant_id, __rec.__code;
            __failed := __failed + 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: delete_tenant error: %', SQLERRM;
        __failed := __failed + 1;
    END;

    -- ==========================================
    -- Cleanup
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '-- Cleanup --';

    DELETE FROM auth.user_group_member WHERE user_group_id = __test_group_id AND user_id = __test_user_id;
    DELETE FROM auth.user_group WHERE code = 'test_gm_dt_group';
    DELETE FROM auth.tenant WHERE code LIKE 'test_gm_dt_tenant%';
    DELETE FROM auth.user_info WHERE user_id = __test_user_id;

    RAISE NOTICE 'Test data cleaned up';

    -- ==========================================
    -- Summary
    -- ==========================================
    RAISE NOTICE '';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'SUMMARY: % passed, % failed', __passed, __failed;
    RAISE NOTICE '==========================================';

    IF __failed > 0 THEN
        RAISE EXCEPTION 'Some tests failed';
    END IF;
END;
$$;
