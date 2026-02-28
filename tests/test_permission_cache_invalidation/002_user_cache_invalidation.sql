set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 4: clear_permission_cache function
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __cache_before int;
    __cache_after int;
BEGIN
    RAISE NOTICE 'TEST 4: clear_permission_cache function';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';

    -- Insert cache entry
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    SELECT count(*) INTO __cache_before FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    PERFORM unsecure.clear_permission_cache('test', __user_id, 1);

    SELECT count(*) INTO __cache_after FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    IF __cache_before > 0 AND __cache_after = 0 THEN
        RAISE NOTICE '  PASS: Cache cleared (% -> %)', __cache_before, __cache_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Cache not cleared (% -> %)', __cache_before, __cache_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: assign_permission invalidates user cache
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __cache_before int;
    __cache_after int;
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 5: assign_permission invalidates user cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';

    -- Populate cache
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    SELECT count(*) INTO __cache_before FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    -- Assign permission to user
    SELECT assignment_id INTO __assignment_id
    FROM unsecure.assign_permission('test', 1, null, null, __user_id, null, 'cache_test_perm', 1);

    SELECT count(*) INTO __cache_after FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    IF __cache_before > 0 AND __cache_after = 0 THEN
        RAISE NOTICE '  PASS: User cache invalidated on assign (% -> %)', __cache_before, __cache_after;
    ELSE
        RAISE EXCEPTION '  FAIL: User cache not invalidated (% -> %)', __cache_before, __cache_after;
    END IF;

    -- Cleanup
    DELETE FROM auth.permission_assignment WHERE assignment_id = __assignment_id;
END $$;

-- ============================================================================
-- TEST 6: unassign_permission invalidates user cache
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __cache_before int;
    __cache_after int;
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 6: unassign_permission invalidates user cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';

    -- Create assignment first
    SELECT assignment_id INTO __assignment_id
    FROM unsecure.assign_permission('test', 1, null, null, __user_id, null, 'cache_test_perm', 1);

    -- Populate cache
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    SELECT count(*) INTO __cache_before FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    -- Unassign permission
    PERFORM unsecure.unassign_permission('test', 1, null, __assignment_id, 1);

    SELECT count(*) INTO __cache_after FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;

    IF __cache_before > 0 AND __cache_after = 0 THEN
        RAISE NOTICE '  PASS: User cache invalidated on unassign (% -> %)', __cache_before, __cache_after;
    ELSE
        RAISE EXCEPTION '  FAIL: User cache not invalidated (% -> %)', __cache_before, __cache_after;
    END IF;
END $$;
