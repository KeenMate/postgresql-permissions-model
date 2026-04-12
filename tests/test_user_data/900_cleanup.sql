set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'User Data Test Suite - Cleanup';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

DO $$
DECLARE
    __admin_id bigint;
    __user_id_1 bigint;
    __user_id_2 bigint;
BEGIN
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    DELETE FROM auth.user_data WHERE user_id IN (__admin_id, __user_id_1, __user_id_2);
    DELETE FROM auth.user_info WHERE user_id IN (__admin_id, __user_id_1, __user_id_2);

    DROP TABLE IF EXISTS _ud_test_data;

    RAISE NOTICE 'CLEANUP: Done';
END $$;
