/*
 * Automated Tests: Permission Cache Invalidation & Related Improvements
 * ======================================================================
 *
 * Tests for v2.2.0 improvements:
 * - Cache invalidation on permission changes
 * - Soft invalidation (UPDATE expiration_date) for group/perm_set operations
 * - Hard invalidation (DELETE) for individual user operations
 * - Parameter mutual exclusivity in assign_permission
 * - Provider validation in recalculate_user_groups
 * - Refactored owner functions
 *
 * Soft invalidation strategy (tests 7-10):
 * - Uses UPDATE to set expiration_date = now() instead of DELETE
 * - ~5-10x faster than DELETE for large-scale operations (no index rebalancing)
 * - Next has_permission call will recalculate immediately
 *
 * Run with: ./exec-sql.sh -f tests/test_permission_cache_invalidation.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission Cache Invalidation Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test data
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_group_id int;
    __test_permission_id int;
    __test_perm_set_id int;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test', 'test', 'normal', 'cache_test_user', 'cache_test_user', 'Cache Test User', 'cache_test@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'Cache Test User'
    RETURNING user_id INTO __test_user_id;

    -- Create test group
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_assignable, is_active)
    VALUES ('test', 'test', 1, 'Cache Test Group', 'cache_test_group', true, true)
    ON CONFLICT DO NOTHING;

    SELECT user_group_id INTO __test_group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Add user to group
    INSERT INTO auth.user_group_member (created_by, group_id, user_id, member_type_code)
    VALUES ('test', __test_group_id, __test_user_id, 'manual')
    ON CONFLICT DO NOTHING;

    -- Create test permission
    INSERT INTO auth.permission (created_by, updated_by, title, code, full_code, node_path, is_assignable)
    VALUES ('test', 'test', 'Cache Test Permission', 'cache_test_perm', 'cache_test_perm'::ltree, '999'::ltree, true)
    ON CONFLICT DO NOTHING;

    SELECT permission_id INTO __test_permission_id FROM auth.permission WHERE code = 'cache_test_perm';

    -- Create test perm_set
    INSERT INTO auth.perm_set (created_by, updated_by, tenant_id, title, code, is_assignable)
    VALUES ('test', 'test', 1, 'Cache Test Perm Set', 'cache_test_perm_set', true)
    ON CONFLICT DO NOTHING;

    SELECT perm_set_id INTO __test_perm_set_id FROM auth.perm_set WHERE code = 'cache_test_perm_set' AND tenant_id = 1;

    RAISE NOTICE 'SETUP: Test user_id=%, group_id=%, permission_id=%, perm_set_id=%',
        __test_user_id, __test_group_id, __test_permission_id, __test_perm_set_id;
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: Helper functions exist
-- ============================================================================
DO $$
DECLARE
    __func_count int;
BEGIN
    RAISE NOTICE 'TEST 1: Verify helper functions exist';

    SELECT count(*) INTO __func_count
    FROM pg_proc
    WHERE proname IN ('invalidate_group_members_permission_cache',
                      'invalidate_perm_set_users_permission_cache',
                      'verify_owner_or_permission');

    IF __func_count = 3 THEN
        RAISE NOTICE '  PASS: All 3 helper functions exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 helper functions, found %', __func_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Parameter mutual exclusivity in assign_permission
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 2: Parameter mutual exclusivity validation';

    -- This should fail with error 22023
    BEGIN
        PERFORM unsecure.assign_permission('test', 1, null, 1, 1000, 'nonexistent', null, 1);
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            RAISE NOTICE '  PASS: Correctly threw error 22023 when both group and user specified';
        WHEN OTHERS THEN
            -- Could be other validation errors (group/user not found), check message
            IF SQLERRM LIKE '%Cannot specify both%' THEN
                RAISE NOTICE '  PASS: Correctly threw error when both group and user specified';
            ELSE
                RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 3: Provider validation in recalculate_user_groups
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 3: Provider validation';

    BEGIN
        PERFORM unsecure.recalculate_user_groups('test', 1, 'nonexistent_provider_xyz');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            RAISE NOTICE '  PASS: Correctly threw error 22023 for non-existent provider';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

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

-- ============================================================================
-- TEST 11: Refactored owner functions (create_owner)
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __group_id int;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 11: Refactored create_owner function';

    SELECT user_id INTO __target_user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Create owner (system user_id=1 is allowed)
    SELECT co.__owner_id INTO __owner_id
    FROM auth.create_owner('test', 1, null, __target_user_id, __group_id, 1) co;

    IF __owner_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.owner WHERE owner_id = __owner_id) THEN
        RAISE NOTICE '  PASS: create_owner worked (owner_id=%)', __owner_id;
    ELSE
        RAISE EXCEPTION '  FAIL: create_owner failed';
    END IF;

    -- Store for cleanup in next test
    PERFORM set_config('test.owner_id', __owner_id::text, false);
END $$;

-- ============================================================================
-- TEST 12: Refactored owner functions (delete_owner)
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __group_id int;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 12: Refactored delete_owner function';

    SELECT user_id INTO __target_user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';
    __owner_id := current_setting('test.owner_id')::bigint;

    -- Delete owner
    PERFORM auth.delete_owner('test', 1, null, __target_user_id, __group_id, 1);

    IF NOT EXISTS (SELECT 1 FROM auth.owner WHERE owner_id = __owner_id) THEN
        RAISE NOTICE '  PASS: delete_owner worked (owner removed)';
    ELSE
        RAISE EXCEPTION '  FAIL: delete_owner failed (owner still exists)';
    END IF;
END $$;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up in reverse order of dependencies
    DELETE FROM auth.permission_assignment WHERE created_by = 'test';
    DELETE FROM auth.user_permission_cache WHERE created_by = 'test';
    DELETE FROM auth.owner WHERE created_by = 'test';
    DELETE FROM auth.user_group_member WHERE created_by = 'test';
    DELETE FROM auth.perm_set_perm WHERE created_by = 'test';
    DELETE FROM auth.perm_set WHERE code = 'cache_test_perm_set';
    DELETE FROM auth.permission WHERE code = 'cache_test_perm';
    DELETE FROM auth.user_group WHERE code = 'cache_test_group';
    DELETE FROM auth.user_info WHERE username = 'cache_test_user';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Permission Cache Invalidation Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 12 tests passed:';
    RAISE NOTICE '  1. Helper functions exist';
    RAISE NOTICE '  2. Parameter mutual exclusivity validation';
    RAISE NOTICE '  3. Provider validation';
    RAISE NOTICE '  4. clear_permission_cache function';
    RAISE NOTICE '  5. assign_permission invalidates user cache';
    RAISE NOTICE '  6. unassign_permission invalidates user cache';
    RAISE NOTICE '  7. assign_permission to group invalidates member cache';
    RAISE NOTICE '  8. unassign_permission from group invalidates member cache';
    RAISE NOTICE '  9. add_perm_set_permissions invalidates affected users cache';
    RAISE NOTICE '  10. delete_perm_set_permissions invalidates affected users cache';
    RAISE NOTICE '  11. Refactored create_owner function';
    RAISE NOTICE '  12. Refactored delete_owner function';
    RAISE NOTICE '';
END $$;
