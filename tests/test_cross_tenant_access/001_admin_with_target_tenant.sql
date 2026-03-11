set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Tests: Admin user (tenant 1) queries with _target_tenant_id
-- Verifies that admin can see specific tenant's data using cross-tenant access
-- ============================================================================

-- ============================================================================
-- TEST 1: search_users with _target_tenant_id sees only that tenant's users
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __user2_id bigint := current_setting('test_ct.user2_id')::bigint;
    __count bigint;
    __found_user_ids bigint[];
BEGIN
    RAISE NOTICE 'TEST 1: search_users - admin with _target_tenant_id sees only that tenant';

    SELECT count(*), array_agg(__user_id)
    INTO __count, __found_user_ids
    FROM auth.search_users(__admin_user_id, 'test_ct', '{"search_text": "ct_regular_user2"}'::jsonb,
                           _tenant_id := 1, _target_tenant_id := __tenant2_id);

    IF __count >= 1 AND __user2_id = ANY(__found_user_ids) THEN
        RAISE NOTICE '  PASS: search_users returned % result(s) for tenant %, found user2', __count, __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected to find user2 (%) in tenant %, got count=%, ids=%',
            __user2_id, __tenant2_id, __count, __found_user_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: search_users with _target_tenant_id does NOT show other tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __user3_id bigint := current_setting('test_ct.user3_id')::bigint;
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 2: search_users - admin targeting tenant 2 does NOT see tenant 3 user';

    SELECT count(*) INTO __count
    FROM auth.search_users(__admin_user_id, 'test_ct', '{"search_text": "ct_regular_user3"}'::jsonb,
                           _tenant_id := 1, _target_tenant_id := __tenant2_id);

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: user3 from tenant 3 not visible when targeting tenant %', __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 results for user3 in tenant %, got %', __tenant2_id, __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: search_user_groups with _target_tenant_id
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __group_t2_id integer := current_setting('test_ct.group_t2_id')::integer;
    __count bigint;
    __found_ids integer[];
BEGIN
    RAISE NOTICE 'TEST 3: search_user_groups - admin with _target_tenant_id sees only that tenant';

    SELECT count(*), array_agg(__user_group_id)
    INTO __count, __found_ids
    FROM auth.search_user_groups(__admin_user_id, 'test_ct', '{"search_text": "CT Tenant2"}'::jsonb,
                                 _tenant_id := 1, _target_tenant_id := __tenant2_id);

    IF __count >= 1 AND __group_t2_id = ANY(__found_ids) THEN
        RAISE NOTICE '  PASS: search_user_groups returned % group(s) for tenant %, found tenant2 group', __count, __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected to find group % in tenant %, got count=%, ids=%',
            __group_t2_id, __tenant2_id, __count, __found_ids;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: search_user_groups with _target_tenant_id excludes other tenants
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 4: search_user_groups - targeting tenant 2 does NOT show tenant 3 groups';

    SELECT count(*) INTO __count
    FROM auth.search_user_groups(__admin_user_id, 'test_ct', '{"search_text": "CT Tenant3"}'::jsonb,
                                 _tenant_id := 1, _target_tenant_id := __tenant2_id);

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: tenant 3 group not visible when targeting tenant %', __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 0 results for tenant 3 group, got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: search_tenants with _target_tenant_id
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant3_id integer := current_setting('test_ct.tenant3_id')::integer;
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 5: search_tenants - admin with _target_tenant_id sees only that tenant';

    SELECT count(*) INTO __count
    FROM auth.search_tenants(__admin_user_id, 'test_ct', '{"search_text": "Cross-Tenant Test Tenant 3"}'::jsonb,
                             _tenant_id := 1, _target_tenant_id := __tenant3_id);

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: search_tenants returned exactly 1 result for tenant %', __tenant3_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected 1 result for tenant %, got %', __tenant3_id, __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: get_perm_sets with _target_tenant_id
-- ============================================================================
DO $$
DECLARE
    __admin_user_id bigint := current_setting('test_ct.admin_user_id')::bigint;
    __tenant2_id integer := current_setting('test_ct.tenant2_id')::integer;
    __count bigint;
    __found_codes text[];
BEGIN
    RAISE NOTICE 'TEST 6: get_perm_sets - admin with _target_tenant_id sees only that tenant';

    SELECT count(*), array_agg(__code)
    INTO __count, __found_codes
    FROM auth.get_perm_sets('test_ct', __admin_user_id, 'test_ct',
                            _tenant_id := 1, _target_tenant_id := __tenant2_id);

    IF __count >= 1 AND 'ct_perm_set_t2' = ANY(__found_codes) THEN
        RAISE NOTICE '  PASS: get_perm_sets returned % set(s) for tenant %, includes ct_perm_set_t2', __count, __tenant2_id;
    ELSE
        RAISE EXCEPTION '  FAIL: expected ct_perm_set_t2 in tenant %, got count=%, codes=%',
            __tenant2_id, __count, __found_codes;
    END IF;
END $$;
