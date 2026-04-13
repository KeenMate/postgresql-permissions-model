set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 8: assign_user_default_groups — assigns user to default group
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __default_group_id int;
    __member_count int;
    __result_count int;
BEGIN
    RAISE NOTICE 'TEST 8: assign_user_default_groups — assigns user to default group';

    __user2_id := current_setting('pchk.user2_id')::bigint;
    __default_group_id := current_setting('pchk.default_group_id')::int;

    -- Remove any existing membership first (clean slate)
    DELETE FROM auth.user_group_member
    WHERE user_id = __user2_id AND user_group_id = __default_group_id;

    -- Call assign_user_default_groups (system user id=1 as admin)
    SELECT count(*) INTO __result_count
    FROM auth.assign_user_default_groups('pchk_test', 1, 'pchk-corr-008', __user2_id, 1);

    -- Verify user is now a member
    SELECT count(*) INTO __member_count
    FROM auth.user_group_member
    WHERE user_id = __user2_id AND user_group_id = __default_group_id;

    IF __member_count = 1 AND __result_count > 0 THEN
        RAISE NOTICE '  PASS: User assigned to default group (% assignments returned)', __result_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 member, got %; result rows=%', __member_count, __result_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: assign_user_default_groups — idempotent (no duplicate members)
-- ============================================================================
DO $$
DECLARE
    __user2_id bigint;
    __default_group_id int;
    __member_count_before int;
    __member_count_after int;
    __result_count int;
BEGIN
    RAISE NOTICE 'TEST 9: assign_user_default_groups — idempotent on second call';

    __user2_id := current_setting('pchk.user2_id')::bigint;
    __default_group_id := current_setting('pchk.default_group_id')::int;

    -- Count members before second call
    SELECT count(*) INTO __member_count_before
    FROM auth.user_group_member
    WHERE user_id = __user2_id AND user_group_id = __default_group_id;

    -- Call again — should be idempotent
    SELECT count(*) INTO __result_count
    FROM auth.assign_user_default_groups('pchk_test', 1, 'pchk-corr-009', __user2_id, 1);

    -- Count members after second call
    SELECT count(*) INTO __member_count_after
    FROM auth.user_group_member
    WHERE user_id = __user2_id AND user_group_id = __default_group_id;

    IF __member_count_before = __member_count_after AND __member_count_after = 1 THEN
        RAISE NOTICE '  PASS: Idempotent — still 1 member after second call (result rows=%)', __result_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 member before and after, got % -> %', __member_count_before, __member_count_after;
    END IF;
END $$;
