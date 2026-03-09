set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Tests: Admin user (tenant 1) queries WITHOUT _target_tenant_id
-- When _tenant_id = 1 and _target_tenant_id is null, admin sees ALL data
-- ============================================================================

-- ============================================================================
-- TEST 7: search_users - admin sees users from all tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __user3_id bigint := current_setting('test_ct.user3_id')::bigint;
    __count bigint;
    __found_user_ids bigint[];
BEGIN
    RAISE NOTICE 'TEST 7: search_users - admin without target sees all tenants';

    SELECT count(*), array_agg(__user_id)
    INTO __count, __found_user_ids
    FROM auth.search_users(__admin_user_id, 'test_ct', _search_text := 'ct_',
                           _tenant_id := 1);

    IF __count >= 3 AND __user2_id = ANY(__found_user_ids) AND __user3_id = ANY(__found_user_ids) THEN
        RAISE NOTICE '  PASS: search_users returned % result(s), includes users from tenants 2 and 3', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected users from all tenants, got count=%, ids=%', __count, __found_user_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: search_user_groups - admin sees groups from all tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __group_t1_id integer := current_setting('test_ct.group_t1_id')::integer;
    __group_t2_id integer := current_setting('test_ct.group_t2_id')::integer;
    __group_t3_id integer := current_setting('test_ct.group_t3_id')::integer;
    __count bigint;
    __found_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 8: search_user_groups - admin without target sees all tenants';

    SELECT count(*), array_agg(__user_group_id)
    INTO __count, __found_ids
    FROM auth.search_user_groups(__admin_user_id, 'test_ct', _search_text := 'CT ',
                                 _tenant_id := 1);

    IF __count >= 3
       AND __group_t1_id = ANY(__found_ids)
       AND __group_t2_id = ANY(__found_ids)
       AND __group_t3_id = ANY(__found_ids) THEN
        RAISE NOTICE '  PASS: search_user_groups returned % group(s) across all tenants', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected groups from all 3 tenants, got count=%, ids=%', __count, __found_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: search_tenants - admin sees all tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __count bigint;
    __found_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 9: search_tenants - admin without target sees all tenants';

    SELECT count(*), array_agg(__tenant_id)
    INTO __count, __found_ids
    FROM auth.search_tenants(__admin_user_id, 'test_ct', _search_text := 'Cross-Tenant Test',
                             _tenant_id := 1);

    IF __count >= 2 AND __tenant2_id = ANY(__found_ids) AND __tenant3_id = ANY(__found_ids) THEN
        RAISE NOTICE '  PASS: search_tenants returned % result(s), includes tenants 2 and 3', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected both test tenants, got count=%, ids=%', __count, __found_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: get_perm_sets - admin sees perm sets from all tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __count bigint;
    __found_codes text[];
BEGIN
    RAISE NOTICE 'TEST 10: get_perm_sets - admin without target sees all tenants';

    SELECT count(*), array_agg(__code)
    INTO __count, __found_codes
    FROM auth.get_perm_sets('test_ct', __admin_user_id, 'test_ct', _tenant_id := 1);

    IF __count >= 3
       AND 'ct_perm_set_t1' = ANY(__found_codes)
       AND 'ct_perm_set_t2' = ANY(__found_codes)
       AND 'ct_perm_set_t3' = ANY(__found_codes) THEN
        RAISE NOTICE '  PASS: get_perm_sets returned % set(s) across all tenants', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected perm sets from all 3 tenants, got count=%, codes=%', __count, __found_codes;
    END IF;
END $$;
