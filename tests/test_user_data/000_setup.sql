set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'User Data Test Suite - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

DO $$
DECLARE
    __user_id_1 bigint;  -- admin (has permissions)
    __user_id_2 bigint;  -- regular user
    __user_id_3 bigint;  -- another regular user
BEGIN
    RAISE NOTICE 'SETUP: Creating test users...';

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('test', 'test', 'UD Admin', 'ud_admin', 'ud_admin@test.com', 'ud_admin@test.com', 'ud_admin@test.com', true)
    RETURNING user_id INTO __user_id_1;

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('test', 'test', 'UD User 1', 'ud_user_1', 'ud_user_1@test.com', 'ud_user_1@test.com', 'ud_user_1@test.com', true)
    RETURNING user_id INTO __user_id_2;

    INSERT INTO auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    VALUES ('test', 'test', 'UD User 2', 'ud_user_2', 'ud_user_2@test.com', 'ud_user_2@test.com', 'ud_user_2@test.com', true)
    RETURNING user_id INTO __user_id_3;

    -- Admin gets system_admin perm set
    PERFORM unsecure.assign_permission_as_system(null::integer, __user_id_1, 'system_admin');

    CREATE TEMP TABLE IF NOT EXISTS _ud_test_data (
        key text PRIMARY KEY,
        val bigint
    );
    DELETE FROM _ud_test_data;
    INSERT INTO _ud_test_data VALUES
        ('admin_id', __user_id_1),
        ('user_id_1', __user_id_2),
        ('user_id_2', __user_id_3);

    RAISE NOTICE 'SETUP: Created admin=%, user1=%, user2=%', __user_id_1, __user_id_2, __user_id_3;
    RAISE NOTICE 'SETUP: Done';
    RAISE NOTICE '';
END $$;
