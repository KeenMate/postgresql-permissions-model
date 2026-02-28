set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
