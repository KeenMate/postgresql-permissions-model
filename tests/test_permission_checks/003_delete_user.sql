set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: delete_user_info — delete user without blacklist
-- ============================================================================
DO $$
DECLARE
    __del_user_id bigint;
    __deleted_username text;
    __user_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 10: delete_user_info — delete user without blacklist';

    __del_user_id := current_setting('pchk.delete_user_id')::bigint;

    -- Delete user (system user id=1 as admin, _blacklist := false)
    SELECT __username INTO __deleted_username
    FROM auth.delete_user_info('pchk_test', 1, 'pchk-corr-010', __del_user_id, 1, false);

    -- Verify user no longer exists
    SELECT exists(SELECT 1 FROM auth.user_info WHERE user_id = __del_user_id) INTO __user_exists;

    IF NOT __user_exists AND __deleted_username = 'pchk_del_user' THEN
        RAISE NOTICE '  PASS: User deleted, username=%, no blacklist', __deleted_username;
    ELSE
        RAISE EXCEPTION '  FAIL: User still exists=% or wrong username=%', __user_exists, __deleted_username;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: delete_user_info — delete user with blacklist
-- ============================================================================
DO $$
DECLARE
    __del_bl_user_id bigint;
    __deleted_username text;
    __user_exists boolean;
    __blacklist_count int;
BEGIN
    RAISE NOTICE 'TEST 11: delete_user_info — delete user with blacklist';

    __del_bl_user_id := current_setting('pchk.delete_bl_user_id')::bigint;

    -- Delete user with blacklist (system user id=1 as admin, _blacklist := true)
    SELECT __username INTO __deleted_username
    FROM auth.delete_user_info('pchk_test', 1, 'pchk-corr-011', __del_bl_user_id, 1, true);

    -- Verify user no longer exists
    SELECT exists(SELECT 1 FROM auth.user_info WHERE user_id = __del_bl_user_id) INTO __user_exists;

    -- Verify blacklist entry was created (username-based)
    SELECT count(*) INTO __blacklist_count
    FROM auth.user_blacklist
    WHERE username = 'pchk_del_bl_user' AND original_user_id = __del_bl_user_id;

    IF NOT __user_exists AND __deleted_username = 'pchk_del_bl_user' AND __blacklist_count > 0 THEN
        RAISE NOTICE '  PASS: User deleted with blacklist, username=%, blacklist entries=%', __deleted_username, __blacklist_count;
    ELSE
        RAISE EXCEPTION '  FAIL: exists=%, username=%, blacklist_count=%', __user_exists, __deleted_username, __blacklist_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: delete_user_info — cannot delete system user
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 12: delete_user_info — cannot delete system user (id=1, is_system=true)';

    BEGIN
        -- Attempt to delete system user (user_id=1, is_system=true)
        PERFORM auth.delete_user_info('pchk_test', 1, 'pchk-corr-012', 1, 1, false);
        RAISE EXCEPTION '  FAIL: Expected exception when deleting system user';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '33002' OR SQLERRM LIKE '%system%' THEN
            RAISE NOTICE '  PASS: System user deletion blocked (state=%, msg=%)', SQLSTATE, SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Unexpected exception: % (state: %)', SQLERRM, SQLSTATE;
        END IF;
    END;
END $$;
