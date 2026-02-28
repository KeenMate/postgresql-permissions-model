set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: Cannot delete a system event code
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 10: Cannot delete a system event code';

    BEGIN
        PERFORM public.delete_event_code('test_ecm', 1, 'test-corr', 10001); -- user_created is system
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31010' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31010 for system event code';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 11: Cannot delete a non-existent event code
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 11: Cannot delete a non-existent event code';

    BEGIN
        PERFORM public.delete_event_code('test_ecm', 1, 'test-corr', 99999);
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31011' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31011 for non-existent event code';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 12: Cannot delete system event message
-- ============================================================================
DO $$
DECLARE
    __system_message_id integer;
BEGIN
    RAISE NOTICE 'TEST 12: Cannot delete a system event message';

    -- Get a system event message (user_created)
    SELECT event_message_id INTO __system_message_id
    FROM const.event_message
    WHERE event_id = 10001 AND language_code = 'en' AND is_active = true
    LIMIT 1;

    IF __system_message_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: No system event message found for event_id 10001';
    END IF;

    BEGIN
        PERFORM public.delete_event_message('test_ecm', 1, 'test-corr', __system_message_id);
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31010' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31010 for system event message (id=%)',
                __system_message_id;
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 13: Cannot delete category with system event codes
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 13: Cannot delete category with system event codes';

    BEGIN
        PERFORM public.delete_event_category('test_ecm', 1, 'test-corr', 'user_event');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31010' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31010 for category with system events';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 14: Cannot delete non-empty category (even with non-system codes)
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 14: Cannot delete non-empty category';

    BEGIN
        PERFORM public.delete_event_category('test_ecm', 1, 'test-corr', 'test_app_event');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31012' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31012 for non-empty category';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 15: Cannot delete non-existent category
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 15: Cannot delete non-existent category';

    BEGIN
        PERFORM public.delete_event_category('test_ecm', 1, 'test-corr', 'nonexistent_category');
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31014' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31014 for non-existent category';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;
