set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Self-update — no permission required
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 1: Self-update — no permission required';
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    -- user_id_1 has NO permissions, but can update own data
    SELECT * FROM auth.update_user_data('test', __user_id, 'test-perm-1', __user_id,
        _preferences := '{"self_updated": true}'::jsonb)
    INTO __result;

    IF (__result.preferences->>'self_updated')::boolean = true THEN
        RAISE NOTICE '  PASS: Self-update succeeded without permissions';
    ELSE
        RAISE EXCEPTION '  FAIL: %', __result.preferences;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Updating another user — requires permission
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
BEGIN
    RAISE NOTICE 'TEST 2: Updating another user without permission — denied';
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    BEGIN
        -- user_id_1 has no permissions, trying to update user_id_2
        PERFORM auth.update_user_data('test', __user_id_1, 'test-perm-2', __user_id_2,
            _settings := '{"hacked": true}'::jsonb);
        RAISE EXCEPTION '  FAIL: Expected permission error but none was thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%does not have required permission%' OR SQLERRM LIKE '%permission%' THEN
            RAISE NOTICE '  PASS: Permission denied as expected: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '  FAIL: Wrong error: %', SQLERRM;
        END IF;
    END;
END $$;

-- ============================================================================
-- TEST 3: Admin updating another user — succeeds
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 3: Admin updating another user — succeeds';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-perm-3', __user_id,
        _custom_data := '{"admin_set": true}'::jsonb)
    INTO __result;

    IF (__result.custom_data->>'admin_set')::boolean = true THEN
        RAISE NOTICE '  PASS: Admin update succeeded';
    ELSE
        RAISE EXCEPTION '  FAIL: %', __result.custom_data;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: get_user_data — self access is free
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 4: get_user_data — self access is free';
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.get_user_data(__user_id, 'test-perm-4', __user_id)
    INTO __result;

    IF __result.user_id = __user_id THEN
        RAISE NOTICE '  PASS: Self-read succeeded';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected own data, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: get_user_data — reading another user requires permission
-- ============================================================================
DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
BEGIN
    RAISE NOTICE 'TEST 5: get_user_data — reading another user requires permission';
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_2' INTO __user_id_2;

    BEGIN
        PERFORM auth.get_user_data(__user_id_1, 'test-perm-5', __user_id_2);
        RAISE EXCEPTION '  FAIL: Expected permission error but none was thrown';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%does not have required permission%' OR SQLERRM LIKE '%permission%' THEN
            RAISE NOTICE '  PASS: Permission denied as expected';
        ELSE
            RAISE EXCEPTION '  FAIL: Wrong error: %', SQLERRM;
        END IF;
    END;
END $$;
