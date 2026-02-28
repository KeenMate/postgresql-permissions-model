set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 7: assign_permission to group invalidates member cache (soft invalidation)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __group_id int;
    __valid_before int;
    __valid_after int;
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 7: assign_permission to group invalidates member cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Populate cache with valid expiration
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    -- Count valid (non-expired) cache entries
    SELECT count(*) INTO __valid_before FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    -- Assign permission to group (triggers soft invalidation)
    SELECT assignment_id INTO __assignment_id
    FROM unsecure.assign_permission('test', 1, null, __group_id, null, null, 'cache_test_perm', 1);

    -- Count valid cache entries after (soft invalidation sets expiration_date = now())
    SELECT count(*) INTO __valid_after FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    IF __valid_before > 0 AND __valid_after = 0 THEN
        RAISE NOTICE '  PASS: Group member cache soft-invalidated on assign (valid: % -> %)', __valid_before, __valid_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Group member cache not invalidated (valid: % -> %)', __valid_before, __valid_after;
    END IF;

    -- Cleanup
    DELETE FROM auth.permission_assignment WHERE assignment_id = __assignment_id;
    DELETE FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;
END $$;

-- ============================================================================
-- TEST 8: unassign_permission from group invalidates member cache (soft invalidation)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __group_id int;
    __valid_before int;
    __valid_after int;
    __assignment_id bigint;
BEGIN
    RAISE NOTICE 'TEST 8: unassign_permission from group invalidates member cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Create assignment first
    SELECT assignment_id INTO __assignment_id
    FROM unsecure.assign_permission('test', 1, null, __group_id, null, null, 'cache_test_perm', 1);

    -- Populate cache with valid expiration
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    -- Count valid cache entries
    SELECT count(*) INTO __valid_before FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    -- Unassign permission from group (triggers soft invalidation)
    PERFORM unsecure.unassign_permission('test', 1, null, __assignment_id, 1);

    -- Count valid cache entries after
    SELECT count(*) INTO __valid_after FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    IF __valid_before > 0 AND __valid_after = 0 THEN
        RAISE NOTICE '  PASS: Group member cache soft-invalidated on unassign (valid: % -> %)', __valid_before, __valid_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Group member cache not invalidated (valid: % -> %)', __valid_before, __valid_after;
    END IF;

    -- Cleanup
    DELETE FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;
END $$;
