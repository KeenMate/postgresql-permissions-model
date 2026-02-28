set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 9: Login failure raises correct exception for user not found
-- (event INSERT is rolled back by PG exception handling -- see file header)
-- ============================================================================
DO $$
DECLARE
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 9: Login raises error 33001 on user not found';

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-notfound', 'regtest_nonexistent@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33001' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33001 (user not found)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33001, got %', __caught_state;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 10: Login failure raises correct exception for user disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 10: Login raises error 33003 on user disabled';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET is_active = false WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-disabled', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33003' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33003 (user disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33003, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_active = true WHERE user_id = __user_id;
END $$;

-- ============================================================================
-- TEST 11: Login failure raises correct exception for user locked
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 11: Login raises error 33004 on user locked';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET is_locked = true WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-locked', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33004' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33004 (user locked)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33004, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET is_locked = false WHERE user_id = __user_id;
END $$;

-- ============================================================================
-- TEST 12: Login failure raises correct exception for identity disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 12: Login raises error 33008 on identity disabled';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_identity SET is_active = false WHERE user_id = __user_id AND provider_code = 'email';

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-identity', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33008' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33008 (identity disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33008, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_identity SET is_active = true WHERE user_id = __user_id AND provider_code = 'email';
END $$;

-- ============================================================================
-- TEST 13: Login failure raises correct exception for login disabled
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __caught_state text;
BEGIN
    RAISE NOTICE 'TEST 13: Login raises error 33005 on can_login=false';

    __user_id := current_setting('test.reg_user1_id')::bigint;
    UPDATE auth.user_info SET can_login = false WHERE user_id = __user_id;

    BEGIN
        PERFORM auth.get_user_by_email_for_authentication(1, 'fail-canlogin', 'regtest_user1@test.com');
        RAISE EXCEPTION '  FAIL: Expected exception was not raised';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __caught_state = RETURNED_SQLSTATE;
        IF __caught_state = '33005' THEN
            RAISE NOTICE '  PASS: Raised SQLSTATE 33005 (login disabled)';
        ELSE
            RAISE EXCEPTION '  FAIL: Expected SQLSTATE 33005, got %', __caught_state;
        END IF;
    END;

    UPDATE auth.user_info SET can_login = true WHERE user_id = __user_id;
END $$;
