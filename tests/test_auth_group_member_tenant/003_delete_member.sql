set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
