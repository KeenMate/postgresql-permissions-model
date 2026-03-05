set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 9: auth.verify_user_by_email — status validation errors
-- ============================================================================

-- 9a: Non-existent email → 33001 (via 52103)
DO $$
DECLARE
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9a: verify_user_by_email — non-existent email --';

    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-09a', 'nonexistent@nowhere.com', 'anyhash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for non-existent email';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33001' THEN
        RAISE NOTICE 'PASS: Non-existent email raised 33001';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33001 for non-existent email, got %', __error_code;
    END IF;
END $$;

-- 9b: Disabled user → 33003 (via 52105)
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9b: verify_user_by_email — disabled user --';

    -- Ensure user is unlocked but disabled
    UPDATE auth.user_info SET is_active = false, is_locked = false WHERE user_id = __test_user_id;

    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-09b', 'autolock@test.com', 'fakehash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for disabled user';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33003' THEN
        RAISE NOTICE 'PASS: Disabled user raised 33003';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33003 for disabled user, got %', __error_code;
    END IF;

    -- Restore user state
    UPDATE auth.user_info SET is_active = true WHERE user_id = __test_user_id;
END $$;

-- 9c: Locked user → 33004 (via 52106)
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9c: verify_user_by_email — locked user --';

    -- Lock the user
    UPDATE auth.user_info SET is_locked = true WHERE user_id = __test_user_id;

    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-09c', 'autolock@test.com', 'fakehash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for locked user';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33004' THEN
        RAISE NOTICE 'PASS: Locked user raised 33004';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33004 for locked user, got %', __error_code;
    END IF;

    -- Restore user state
    UPDATE auth.user_info SET is_locked = false WHERE user_id = __test_user_id;
END $$;

-- 9d: can_login = false → 33005 (via 52112)
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9d: verify_user_by_email — can_login disabled --';

    -- Disable login
    UPDATE auth.user_info SET can_login = false WHERE user_id = __test_user_id;

    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-09d', 'autolock@test.com', 'fakehash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for can_login=false';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33005' THEN
        RAISE NOTICE 'PASS: can_login=false raised 33005';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33005 for can_login=false, got %', __error_code;
    END IF;

    -- Restore user state
    UPDATE auth.user_info SET can_login = true WHERE user_id = __test_user_id;
END $$;

-- 9e: Identity disabled → 33008 (via 52110)
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9e: verify_user_by_email — identity disabled --';

    -- Disable email identity
    UPDATE auth.user_identity SET is_active = false WHERE user_id = __test_user_id AND provider_code = 'email';

    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-09e', 'autolock@test.com', 'fakehash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for disabled identity';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    IF __error_code = '33008' THEN
        RAISE NOTICE 'PASS: Disabled identity raised 33008';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected 33008 for disabled identity, got %', __error_code;
    END IF;

    -- Restore identity state
    UPDATE auth.user_identity SET is_active = true WHERE user_id = __test_user_id AND provider_code = 'email';
END $$;
