set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 9: add_perm_set_permissions invalidates affected users cache (soft invalidation)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __perm_set_id int;
    __valid_before int;
    __valid_after int;
BEGIN
    RAISE NOTICE 'TEST 9: add_perm_set_permissions invalidates affected users cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT perm_set_id INTO __perm_set_id FROM auth.perm_set WHERE code = 'cache_test_perm_set' AND tenant_id = 1;

    -- Assign perm_set to user
    INSERT INTO auth.permission_assignment (created_by, tenant_id, user_id, perm_set_id)
    VALUES ('test', 1, __user_id, __perm_set_id)
    ON CONFLICT DO NOTHING;

    -- Populate cache with valid expiration
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    -- Count valid cache entries
    SELECT count(*) INTO __valid_before FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    -- Add permission to perm_set (triggers soft invalidation)
    PERFORM unsecure.add_perm_set_permissions('test', 1, null, __perm_set_id, ARRAY['cache_test_perm'], 1);

    -- Count valid cache entries after
    SELECT count(*) INTO __valid_after FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    IF __valid_before > 0 AND __valid_after = 0 THEN
        RAISE NOTICE '  PASS: Perm set users cache soft-invalidated on add (valid: % -> %)', __valid_before, __valid_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Perm set users cache not invalidated (valid: % -> %)', __valid_before, __valid_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: delete_perm_set_permissions invalidates affected users cache (soft invalidation)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __perm_set_id int;
    __valid_before int;
    __valid_after int;
BEGIN
    RAISE NOTICE 'TEST 10: delete_perm_set_permissions invalidates affected users cache';

    SELECT user_id INTO __user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT perm_set_id INTO __perm_set_id FROM auth.perm_set WHERE code = 'cache_test_perm_set' AND tenant_id = 1;

    -- Populate cache with valid expiration
    INSERT INTO auth.user_permission_cache (created_by, user_id, tenant_id, tenant_uuid, groups, permissions, expiration_date)
    SELECT 'test', __user_id, 1, t.uuid, ARRAY['test'], ARRAY['test'], now() + interval '1 hour'
    FROM auth.tenant t WHERE t.tenant_id = 1
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET expiration_date = now() + interval '1 hour';

    -- Count valid cache entries
    SELECT count(*) INTO __valid_before FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    -- Remove permission from perm_set (triggers soft invalidation)
    PERFORM unsecure.delete_perm_set_permissions('test', 1, null, __perm_set_id, ARRAY['cache_test_perm'], 1);

    -- Count valid cache entries after
    SELECT count(*) INTO __valid_after FROM auth.user_permission_cache
    WHERE user_id = __user_id AND tenant_id = 1 AND expiration_date > now();

    IF __valid_before > 0 AND __valid_after = 0 THEN
        RAISE NOTICE '  PASS: Perm set users cache soft-invalidated on delete (valid: % -> %)', __valid_before, __valid_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Perm set users cache not invalidated (valid: % -> %)', __valid_before, __valid_after;
    END IF;

    -- Cleanup
    DELETE FROM auth.user_permission_cache WHERE user_id = __user_id AND tenant_id = 1;
END $$;
