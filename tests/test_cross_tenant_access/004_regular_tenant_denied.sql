set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Tests: Regular user (tenant 2) trying cross-tenant access gets error 34002
-- Any _target_tenant_id from a non-admin tenant must be rejected
-- ============================================================================

-- ============================================================================
-- TEST 15: search_users - cross-tenant from non-admin tenant raises 34002
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 15: search_users - cross-tenant from non-admin tenant raises 34002';

    BEGIN
        PERFORM * FROM auth.search_users(__user2_id, 'test_ct',
                                         _tenant_id := __tenant2_id,
                                         _target_tenant_id := __tenant3_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: search_users raised error 34002 as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 16: search_user_groups - cross-tenant from non-admin tenant raises 34002
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 16: search_user_groups - cross-tenant from non-admin tenant raises 34002';

    BEGIN
        PERFORM * FROM auth.search_user_groups(__user2_id, 'test_ct',
                                               _tenant_id := __tenant2_id,
                                               _target_tenant_id := __tenant3_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: search_user_groups raised error 34002 as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 17: search_tenants - cross-tenant from non-admin tenant raises 34002
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 17: search_tenants - cross-tenant from non-admin tenant raises 34002';

    BEGIN
        PERFORM * FROM auth.search_tenants(__user2_id, 'test_ct',
                                           _tenant_id := __tenant2_id,
                                           _target_tenant_id := __tenant3_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: search_tenants raised error 34002 as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 18: get_perm_sets - cross-tenant from non-admin tenant raises 34002
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 18: get_perm_sets - cross-tenant from non-admin tenant raises 34002';

    BEGIN
        PERFORM * FROM auth.get_perm_sets('test_ct', __user2_id, 'test_ct',
                                          _tenant_id := __tenant2_id,
                                          _target_tenant_id := __tenant3_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: get_perm_sets raised error 34002 as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 19: search_user_group_mappings - cross-tenant from non-admin raises 34002
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 19: search_user_group_mappings - cross-tenant from non-admin raises 34002';

    BEGIN
        PERFORM * FROM auth.search_user_group_mappings(__user2_id, 'test_ct',
                                                       _tenant_id := __tenant2_id,
                                                       _target_tenant_id := __tenant3_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: search_user_group_mappings raised error 34002 as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 20: Even targeting own tenant with _target_tenant_id is denied for non-admin
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __err_code text;
BEGIN
    RAISE NOTICE 'TEST 20: search_users - targeting own tenant with _target_tenant_id still denied for non-admin';

    BEGIN
        PERFORM * FROM auth.search_users(__user2_id, 'test_ct',
                                         _tenant_id := __tenant2_id,
                                         _target_tenant_id := __tenant2_id);
        RAISE EXCEPTION '  FAIL: expected error 34002, but call succeeded';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '34002' THEN
            RAISE NOTICE '  PASS: even own tenant in _target_tenant_id is denied for non-admin tenant';
        ELSE
            RAISE EXCEPTION '  FAIL: expected error 34002, got % (%)', __err_code, SQLERRM;
        END IF;
    END;
END $$;
