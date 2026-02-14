/*
 * Automated Tests: Auth-Layer Group Member & Tenant Functions
 * ============================================================
 *
 * Tests for auth-layer functions that were missing coverage:
 * - auth.can_manage_user_group (ambiguous user_group_id fix)
 * - auth.create_user_group_member (calls can_manage_user_group)
 * - auth.delete_user_group_member (calls can_manage_user_group)
 * - auth.get_user_group_members (auth wrapper)
 * - auth.get_user_available_tenants (ambiguous column fix)
 * - auth.get_user_assigned_groups
 *
 * These tests exercise the auth layer (with permission checks),
 * not just the unsecure layer that existing tests covered.
 *
 * Run with: ./exec-sql.sh -f tests/test_auth_group_member_tenant.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Auth Group Member & Tenant Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Create test user and group using system user (id=1)
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
    __test_target_id bigint;
    __test_group_id int;
BEGIN
    RAISE NOTICE 'SETUP: Creating test data...';

    -- Create test user who will perform operations (needs permissions)
    -- Use system user (id=1) which has system_admin perm set
    SELECT user_id INTO __test_user_id FROM auth.user_info WHERE user_id = 1;
    IF __test_user_id IS NULL THEN
        RAISE EXCEPTION 'SETUP FAILED: System user (id=1) not found';
    END IF;

    -- Create target user to be added/removed from groups
    INSERT INTO auth.user_info (created_by, updated_by, user_type_code, username, original_username, display_name, email)
    VALUES ('test_agmt', 'test_agmt', 'normal', 'agmt_target_user', 'agmt_target_user', 'AGMT Target User', 'agmt_target@test.com')
    ON CONFLICT (username) DO UPDATE SET display_name = 'AGMT Target User'
    RETURNING user_id INTO __test_target_id;

    -- Create test group (non-system, assignable, active)
    INSERT INTO auth.user_group (created_by, updated_by, tenant_id, title, code, is_assignable, is_active, is_external, is_system)
    VALUES ('test_agmt', 'test_agmt', 1, 'AGMT Test Group', 'agmt_test_group', true, true, false, false)
    ON CONFLICT DO NOTHING;

    SELECT user_group_id INTO __test_group_id FROM auth.user_group WHERE code = 'agmt_test_group';

    -- Store IDs for subsequent tests
    PERFORM set_config('test_agmt.user_id', __test_user_id::text, false);
    PERFORM set_config('test_agmt.target_id', __test_target_id::text, false);
    PERFORM set_config('test_agmt.group_id', __test_group_id::text, false);

    RAISE NOTICE 'SETUP: user_id=%, target_id=%, group_id=%', __test_user_id, __test_target_id, __test_group_id;
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: auth.create_user_group_member succeeds (exercises can_manage_user_group)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __member_id bigint;
BEGIN
    RAISE NOTICE 'TEST 1: auth.create_user_group_member - add member via auth layer';

    SELECT __user_group_member_id INTO __member_id
    FROM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    IF __member_id IS NOT NULL THEN
        RAISE NOTICE '  PASS: Member created (member_id=%)', __member_id;
    ELSE
        RAISE EXCEPTION '  FAIL: create_user_group_member returned null';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: auth.get_user_group_members returns the added member
-- ============================================================================
DO $$
DECLARE
    ___user_id bigint := current_setting('test_agmt.user_id')::bigint;
    ___group_id int := current_setting('test_agmt.group_id')::int;
    ___count int;
BEGIN
    RAISE NOTICE 'TEST 2: auth.get_user_group_members - list members via auth layer';

    SELECT count(*) INTO ___count
    FROM auth.get_user_group_members('test_agmt', ___user_id, 'test-agmt-corr', ___group_id);

    IF ___count >= 1 THEN
        RAISE NOTICE '  PASS: Found % member(s) in group', ___count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 1 member, found %', ___count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: auth.get_user_assigned_groups shows the group for target user
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __count int;
    __found_code text;
BEGIN
    RAISE NOTICE 'TEST 3: auth.get_user_assigned_groups - target user is in group';

    SELECT count(*) INTO __count
    FROM auth.get_user_assigned_groups(__user_id, 'test-agmt-corr', __target_id)
    WHERE __user_group_code = 'agmt_test_group';

    IF __count = 1 THEN
        RAISE NOTICE '  PASS: Target user found in agmt_test_group';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 membership in agmt_test_group, found %', __count;
    END IF;
END $$;

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

-- ============================================================================
-- TEST 6: auth.delete_user_group_member succeeds
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __count_before int;
    __count_after int;
BEGIN
    RAISE NOTICE 'TEST 6: auth.delete_user_group_member - remove member via auth layer';

    SELECT count(*) INTO __count_before
    FROM auth.user_group_member WHERE user_group_id = __group_id AND user_id = __target_id;

    PERFORM auth.delete_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    SELECT count(*) INTO __count_after
    FROM auth.user_group_member WHERE user_group_id = __group_id AND user_id = __target_id;

    IF __count_before = 1 AND __count_after = 0 THEN
        RAISE NOTICE '  PASS: Member removed (% -> %)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 -> 0, got % -> %', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: auth.get_user_available_tenants returns empty after removal
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __count int;
BEGIN
    RAISE NOTICE 'TEST 7: auth.get_user_available_tenants - empty after member removal';

    SELECT count(*) INTO __count
    FROM auth.get_user_available_tenants(__user_id, 'test-agmt-corr', __target_id);

    IF __count = 0 THEN
        RAISE NOTICE '  PASS: No available tenants after group removal';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 tenants, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: auth.create_user_group_member on inactive group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    RAISE NOTICE 'TEST 8: auth.create_user_group_member - inactive group rejected';

    -- Deactivate the group
    UPDATE auth.user_group SET is_active = false, updated_by = 'test_agmt' WHERE user_group_id = __group_id;

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for inactive group';
    EXCEPTION
        WHEN SQLSTATE '33012' THEN
            RAISE NOTICE '  PASS: Correctly rejected inactive group (33012)';
        WHEN OTHERS THEN
            -- Also accept legacy error code
            IF SQLSTATE = '52172' THEN
                RAISE NOTICE '  PASS: Correctly rejected inactive group (52172)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;

    -- Restore
    UPDATE auth.user_group SET is_active = true, updated_by = 'test_agmt' WHERE user_group_id = __group_id;
END $$;

-- ============================================================================
-- TEST 9: auth.create_user_group_member on external group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    RAISE NOTICE 'TEST 9: auth.create_user_group_member - external group rejected';

    -- Set group as external
    UPDATE auth.user_group SET is_external = true, updated_by = 'test_agmt' WHERE user_group_id = __group_id;

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for external group';
    EXCEPTION
        WHEN SQLSTATE '33013' THEN
            RAISE NOTICE '  PASS: Correctly rejected external group (33013)';
        WHEN OTHERS THEN
            IF SQLSTATE = '52173' THEN
                RAISE NOTICE '  PASS: Correctly rejected external group (52173)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;

    -- Restore
    UPDATE auth.user_group SET is_external = false, updated_by = 'test_agmt' WHERE user_group_id = __group_id;
END $$;

-- ============================================================================
-- TEST 10: auth.create_user_group_member on nonexistent group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
BEGIN
    RAISE NOTICE 'TEST 10: auth.create_user_group_member - nonexistent group rejected';

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', -999, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent group';
    EXCEPTION
        WHEN SQLSTATE '33011' THEN
            RAISE NOTICE '  PASS: Correctly raised group not found (33011)';
        WHEN OTHERS THEN
            IF SQLSTATE = '52171' THEN
                RAISE NOTICE '  PASS: Correctly raised group not found (52171)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 11: Re-add and verify round-trip works
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __member_id bigint;
    __tenant_count int;
BEGIN
    RAISE NOTICE 'TEST 11: Full round-trip - add member, check tenant, remove member';

    -- Add
    SELECT __user_group_member_id INTO __member_id
    FROM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    -- Check tenant visible
    SELECT count(*) INTO __tenant_count
    FROM auth.get_user_available_tenants(__user_id, 'test-agmt-corr', __target_id);

    -- Remove
    PERFORM auth.delete_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    IF __member_id IS NOT NULL AND __tenant_count >= 1 THEN
        RAISE NOTICE '  PASS: Round-trip complete (member_id=%, tenants=%)', __member_id, __tenant_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Round-trip failed (member_id=%, tenants=%)', __member_id, __tenant_count;
    END IF;
END $$;

-- ============================================================================
-- CLEANUP
-- ============================================================================
DO $$
DECLARE
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Remove any leftover memberships
    DELETE FROM auth.user_group_member WHERE user_group_id = __group_id;

    -- Remove test group
    DELETE FROM auth.user_group WHERE user_group_id = __group_id;

    -- Remove test user
    DELETE FROM auth.user_info WHERE user_id = __target_id;

    -- Clean up journal entries
    DELETE FROM journal WHERE created_by = 'test_agmt';

    RAISE NOTICE 'CLEANUP: Done';
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Auth Group Member & Tenant Tests - Complete';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;
