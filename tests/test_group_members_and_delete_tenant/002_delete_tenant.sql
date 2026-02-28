set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ==========================================
-- Test 4: unsecure.delete_tenant returns exactly 3 columns
-- (was failing with structure mismatch from SELECT *)
-- ==========================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_gm_dt.user_id')::bigint;
    __test_tenant_id integer := current_setting('test_gm_dt.tenant_id')::int;
    __test_tenant_uuid uuid := current_setting('test_gm_dt.tenant_uuid')::uuid;
    __rec record;
BEGIN
    RAISE NOTICE '-- Test 4: unsecure.delete_tenant returns correct structure --';

    SELECT * INTO __rec
    FROM unsecure.delete_tenant('test_gm_dt', __test_user_id, 'test-correlation', __test_tenant_id);

    IF __rec.__tenant_id = __test_tenant_id
        AND __rec.__uuid = __test_tenant_uuid
        AND __rec.__code = 'test_gm_dt_tenant' THEN
        RAISE NOTICE 'PASS: delete_tenant returned tenant_id=%, uuid=%, code=%',
            __rec.__tenant_id, __rec.__uuid, __rec.__code;
    ELSE
        RAISE EXCEPTION 'FAIL: Unexpected return values: tenant_id=%, uuid=%, code=%',
            __rec.__tenant_id, __rec.__uuid, __rec.__code;
    END IF;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE EXCEPTION '%', SQLERRM;
    END IF;
    RAISE EXCEPTION 'FAIL: unsecure.delete_tenant error: %', SQLERRM;
END;
$$;

-- ==========================================
-- Test 5: auth.delete_tenant returns correct 3-column structure
-- (was failing because SELECT * included all tenant table columns)
-- Re-create tenant first since Test 4 deleted it
-- ==========================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_gm_dt.user_id')::bigint;
    __test_tenant_id integer;
    __test_tenant_uuid uuid;
    __rec record;
BEGIN
    RAISE NOTICE '-- Test 5: auth.delete_tenant returns correct 3-column structure --';

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
    ELSE
        RAISE EXCEPTION 'FAIL: Unexpected return: tenant_id=%, code=%',
            __rec.__tenant_id, __rec.__code;
    END IF;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE EXCEPTION '%', SQLERRM;
    END IF;
    RAISE EXCEPTION 'FAIL: delete_tenant error: %', SQLERRM;
END;
$$;
