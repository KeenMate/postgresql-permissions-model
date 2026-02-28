set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Helper functions exist
-- ============================================================================
DO $$
DECLARE
    __func_count int;
BEGIN
    RAISE NOTICE 'TEST 1: Verify helper functions exist';

    SELECT count(*) INTO __func_count
    FROM pg_proc
    WHERE proname IN ('invalidate_group_members_permission_cache',
                      'invalidate_perm_set_users_permission_cache',
                      'verify_owner_or_permission');

    IF __func_count = 3 THEN
        RAISE NOTICE '  PASS: All 3 helper functions exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 helper functions, found %', __func_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Parameter mutual exclusivity in assign_permission
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 2: Parameter mutual exclusivity validation';

    -- This should fail with error 22023
    BEGIN
        PERFORM unsecure.assign_permission('test', 1, null, 1, 1000, 'nonexistent', null, 1);
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            RAISE NOTICE '  PASS: Correctly threw error 22023 when both group and user specified';
        WHEN OTHERS THEN
            -- Could be other validation errors (group/user not found), check message
            IF SQLERRM LIKE '%Cannot specify both%' THEN
                RAISE NOTICE '  PASS: Correctly threw error when both group and user specified';
            ELSE
                RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;

-- ============================================================================
-- TEST 3: Provider validation in recalculate_user_groups
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 3: Provider validation';

    BEGIN
        PERFORM unsecure.recalculate_user_groups('test', 1, 'nonexistent_provider_xyz');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            RAISE NOTICE '  PASS: Correctly threw error 22023 for non-existent provider';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;
