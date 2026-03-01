set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Re-add target to group (removed in 003, re-added/removed in 005)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);
END $$;

-- ============================================================================
-- TEST 12: is_group_member returns true for actual member
-- ============================================================================
DO $$
DECLARE
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 12: is_group_member returns true for actual member';

    __result := auth.is_group_member(__target_id, 'test-agmt-corr', __group_id, 1);

    IF __result = true THEN
        RAISE NOTICE '  PASS: is_group_member returned true';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: is_group_member returns false for non-member
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 13: is_group_member returns false for non-member';

    -- System user (id=1) is not a member of the test group
    __result := auth.is_group_member(__user_id, 'test-agmt-corr', __group_id, 1);

    IF __result = false THEN
        RAISE NOTICE '  PASS: is_group_member returned false for non-member';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected false, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: is_group_member returns false after member removal
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __before boolean;
    __after boolean;
BEGIN
    RAISE NOTICE 'TEST 14: is_group_member returns false after removal';

    __before := auth.is_group_member(__target_id, 'test-agmt-corr', __group_id, 1);

    PERFORM auth.delete_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    __after := auth.is_group_member(__target_id, 'test-agmt-corr', __group_id, 1);

    IF __before = true AND __after = false THEN
        RAISE NOTICE '  PASS: is_group_member true -> false after removal';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true -> false, got % -> %', __before, __after;
    END IF;
END $$;

-- ============================================================================
-- TEST 15: can_manage_user_group succeeds for system user (tenant owner)
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __result boolean;
BEGIN
    RAISE NOTICE 'TEST 15: can_manage_user_group succeeds for system user';

    __result := auth.can_manage_user_group(__user_id, 'test-agmt-corr', __group_id, 'groups.create_member', 1);

    IF __result = true THEN
        RAISE NOTICE '  PASS: can_manage_user_group returned true';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected true, got %', __result;
    END IF;
END $$;
