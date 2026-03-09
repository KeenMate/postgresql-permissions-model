set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Tests: Regular user (tenant 2) can only see own tenant's data
-- ============================================================================

-- ============================================================================
-- TEST 11: search_users - regular user sees only own tenant
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __user3_id bigint := current_setting('test_ct.user3_id')::bigint;
    __count bigint;
    __found_user_ids bigint[];
BEGIN
    RAISE NOTICE 'TEST 11: search_users - regular user (tenant 2) sees only own tenant';

    SELECT count(*), array_agg(__user_id)
    INTO __count, __found_user_ids
    FROM auth.search_users(__user2_id, 'test_ct', _search_text := 'ct_',
                           _tenant_id := __tenant2_id);

    -- Should find user2 (own tenant) but NOT user3 (tenant 3) or admin (tenant 1)
    IF __user2_id = ANY(__found_user_ids) THEN
        IF __user3_id = ANY(coalesce(__found_user_ids, array[]::bigint[])) THEN
            RAISE EXCEPTION '  FAIL: user3 from tenant 3 should NOT be visible to tenant 2 user';
        END IF;
        RAISE NOTICE '  PASS: search_users returned % result(s), only own tenant data', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected to find own user (%), got ids=%', __user2_id, __found_user_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: search_user_groups - regular user sees only own tenant's groups
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __group_t2_id integer := current_setting('test_ct.group_t2_id')::integer;
    __group_t1_id integer := current_setting('test_ct.group_t1_id')::integer;
    __group_t3_id integer := current_setting('test_ct.group_t3_id')::integer;
    __count bigint;
    __found_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 12: search_user_groups - regular user (tenant 2) sees only own tenant';

    SELECT count(*), array_agg(__user_group_id)
    INTO __count, __found_ids
    FROM auth.search_user_groups(__user2_id, 'test_ct', _search_text := 'CT ',
                                 _tenant_id := __tenant2_id);

    -- Should find tenant 2 group but NOT tenant 1 or 3 groups
    IF __group_t2_id = ANY(coalesce(__found_ids, array[]::integer[])) THEN
        IF __group_t1_id = ANY(__found_ids) OR __group_t3_id = ANY(__found_ids) THEN
            RAISE EXCEPTION '  FAIL: groups from other tenants should NOT be visible, got ids=%', __found_ids;
        END IF;
        RAISE NOTICE '  PASS: search_user_groups returned % group(s), only own tenant data', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected to find own group (%), got ids=%', __group_t2_id, __found_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: search_tenants - regular user sees only own tenant
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __count bigint;
    __found_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 13: search_tenants - regular user (tenant 2) sees only own tenant';

    SELECT count(*), array_agg(__tenant_id)
    INTO __count, __found_ids
    FROM auth.search_tenants(__user2_id, 'test_ct', _search_text := 'Cross-Tenant Test',
                             _tenant_id := __tenant2_id);

    IF __count = 1 AND __tenant2_id = ANY(__found_ids) THEN
        IF __tenant3_id = ANY(__found_ids) THEN
            RAISE EXCEPTION '  FAIL: tenant 3 should NOT be visible to tenant 2 user';
        END IF;
        RAISE NOTICE '  PASS: search_tenants returned only own tenant (%)' , __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 1 result (own tenant %), got count=%, ids=%',
            __tenant2_id, __count, __found_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: get_perm_sets - regular user sees only own tenant's perm sets
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __count bigint;
    __found_codes text[];
BEGIN
    RAISE NOTICE 'TEST 14: get_perm_sets - regular user (tenant 2) sees only own tenant';

    SELECT count(*), array_agg(__code)
    INTO __count, __found_codes
    FROM auth.get_perm_sets('test_ct', __user2_id, 'test_ct', _tenant_id := __tenant2_id);

    IF 'ct_perm_set_t2' = ANY(coalesce(__found_codes, array[]::text[])) THEN
        IF 'ct_perm_set_t1' = ANY(__found_codes) OR 'ct_perm_set_t3' = ANY(__found_codes) THEN
            RAISE EXCEPTION '  FAIL: perm sets from other tenants should NOT be visible, got codes=%', __found_codes;
        END IF;
        RAISE NOTICE '  PASS: get_perm_sets returned % set(s), only own tenant', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected ct_perm_set_t2, got codes=%', __found_codes;
    END IF;
END $$;
