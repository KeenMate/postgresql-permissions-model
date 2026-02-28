set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ==========================================
-- Test 1: get_user_group_members executes without error
-- (was failing with: column ugm.created_at_by does not exist)
-- ==========================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_gm_dt.user_id')::bigint;
    __test_group_id integer := current_setting('test_gm_dt.group_id')::int;
    __count int;
BEGIN
    RAISE NOTICE '-- Test 1: get_user_group_members executes without column error --';

    SELECT count(*) INTO __count
    FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, __test_group_id, 1);

    RAISE NOTICE 'PASS: get_user_group_members returned % row(s)', __count;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: get_user_group_members error: %', SQLERRM;
END;
$$;

-- ==========================================
-- Test 2: get_user_group_members returns correct columns
-- ==========================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_gm_dt.user_id')::bigint;
    __test_group_id integer := current_setting('test_gm_dt.group_id')::int;
    __rec record;
BEGIN
    RAISE NOTICE '-- Test 2: get_user_group_members returns expected data --';

    SELECT * INTO __rec
    FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, __test_group_id, 1)
    LIMIT 1;

    IF __rec.__created_by = 'test_gm_dt'
        AND __rec.__user_display_name = 'Test GM DT User'
        AND __rec.__member_type_code = 'manual' THEN
        RAISE NOTICE 'PASS: Returned correct created_by=%, display_name=%, type=%',
            __rec.__created_by, __rec.__user_display_name, __rec.__member_type_code;
    ELSE
        RAISE EXCEPTION 'FAIL: Unexpected values: created_by=%, display_name=%, type=%',
            __rec.__created_by, __rec.__user_display_name, __rec.__member_type_code;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: get_user_group_members error: %', SQLERRM;
END;
$$;

-- ==========================================
-- Test 3: get_user_group_members with invalid group raises error
-- ==========================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test_gm_dt.user_id')::bigint;
BEGIN
    RAISE NOTICE '-- Test 3: get_user_group_members with invalid group raises error --';

    PERFORM * FROM unsecure.get_user_group_members('test_gm_dt', __test_user_id, -999, 1);
    RAISE EXCEPTION 'FAIL: Should have raised error for non-existent group';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL:%' THEN
        RAISE EXCEPTION '%', SQLERRM;
    END IF;
    RAISE NOTICE 'PASS: Correctly raised error for non-existent group: %', SQLERRM;
END;
$$;
