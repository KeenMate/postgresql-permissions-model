set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 8: auth.create_user_group_member on inactive group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    RAISE NOTICE 'TEST 8: auth.create_user_group_member - inactive group rejected';

    -- Deactivate the group
    UPDATE auth.user_group SET is_active = false, updated_by = 'test_agmt' WHERE user_group_id = __group_id;

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for inactive group';
    EXCEPTION
        WHEN SQLSTATE '33012' THEN
            RAISE NOTICE '  PASS: Correctly rejected inactive group (33012)';
        WHEN OTHERS THEN
            -- Also accept legacy error code
            IF SQLSTATE = '52172' THEN
                RAISE NOTICE '  PASS: Correctly rejected inactive group (52172)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;

    -- Restore
    UPDATE auth.user_group SET is_active = true, updated_by = 'test_agmt' WHERE user_group_id = __group_id;
END $$;

-- ============================================================================
-- TEST 9: auth.create_user_group_member on external group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
BEGIN
    RAISE NOTICE 'TEST 9: auth.create_user_group_member - external group rejected';

    -- Set group as external
    UPDATE auth.user_group SET is_external = true, updated_by = 'test_agmt' WHERE user_group_id = __group_id;

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for external group';
    EXCEPTION
        WHEN SQLSTATE '33013' THEN
            RAISE NOTICE '  PASS: Correctly rejected external group (33013)';
        WHEN OTHERS THEN
            IF SQLSTATE = '52173' THEN
                RAISE NOTICE '  PASS: Correctly rejected external group (52173)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;

    -- Restore
    UPDATE auth.user_group SET is_external = false, updated_by = 'test_agmt' WHERE user_group_id = __group_id;
END $$;

-- ============================================================================
-- TEST 10: auth.create_user_group_member on nonexistent group fails
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
BEGIN
    RAISE NOTICE 'TEST 10: auth.create_user_group_member - nonexistent group rejected';

    BEGIN
        PERFORM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', -999, __target_id);
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent group';
    EXCEPTION
        WHEN SQLSTATE '33011' THEN
            RAISE NOTICE '  PASS: Correctly raised group not found (33011)';
        WHEN OTHERS THEN
            IF SQLSTATE = '52171' THEN
                RAISE NOTICE '  PASS: Correctly raised group not found (52171)';
            ELSE
                RAISE EXCEPTION '  FAIL: Unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;
