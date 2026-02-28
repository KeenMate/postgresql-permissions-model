set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 4: auth.get_user_available_tenants returns tenants for member
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 4: auth.get_user_available_tenants - returns tenants for user';

    SELECT count(*) INTO __count
    FROM auth.get_user_available_tenants(__user_id, 'test-agmt-corr', __target_id);

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Found % available tenant(s) for target user', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 1 tenant, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: auth.get_user_available_tenants returns correct columns
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 5: auth.get_user_available_tenants - correct column values';

    SELECT * INTO __rec
    FROM auth.get_user_available_tenants(__user_id, 'test-agmt-corr', __target_id)
    LIMIT 1;

    IF __rec.__tenant_id IS NOT NULL
        AND __rec.__tenant_uuid IS NOT NULL
        AND __rec.__tenant_code IS NOT NULL
        AND __rec.__tenant_title IS NOT NULL THEN
        RAISE NOTICE '  PASS: tenant_id=%, code=%, title=%', __rec.__tenant_id, __rec.__tenant_code, __rec.__tenant_title;
    ELSE
        RAISE EXCEPTION '  FAIL: Some columns are null (id=%, uuid=%, code=%, title=%)',
            __rec.__tenant_id, __rec.__tenant_uuid, __rec.__tenant_code, __rec.__tenant_title;
    END IF;
END $$;
