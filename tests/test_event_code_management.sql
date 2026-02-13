/*
 * Automated Tests: Dynamic Event Code Management
 * ================================================
 *
 * Tests for event category/code/message CRUD functions and system protection:
 * - Creating custom event categories, codes, and messages
 * - Range validation (event ID must be within category range)
 * - Category existence validation
 * - System event protection (cannot delete system events)
 * - Cascading deletes (event code deletes related messages)
 * - Category delete protection (non-empty category)
 * - Integration with create_journal_message
 *
 * Run with: ./exec-sql.sh -f tests/test_event_code_management.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Event Code Management Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: Create a custom event category
-- ============================================================================
DO $$
DECLARE
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 1: Create a custom event category';

    SELECT * INTO __rec
    FROM public.create_event_category(
        'test_ecm', 1, 'test-corr',
        'test_app_event', 'Test Application Events', 90001, 90999, false
    );

    IF __rec.category_code = 'test_app_event'
        AND __rec.range_start = 90001
        AND __rec.range_end = 90999
        AND __rec.is_error = false THEN
        RAISE NOTICE '  PASS: Created category "%", range %-%, is_error=%',
            __rec.category_code, __rec.range_start, __rec.range_end, __rec.is_error;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected category values: code=%, range=%-%, is_error=%',
            __rec.category_code, __rec.range_start, __rec.range_end, __rec.is_error;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Create a custom event code within valid range
-- ============================================================================
DO $$
DECLARE
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 2: Create a custom event code within valid range';

    SELECT * INTO __rec
    FROM public.create_event_code(
        'test_ecm', 1, 'test-corr',
        90001, 'test_order_created', 'test_app_event',
        'Order Created', 'A new order was created', false
    );

    IF __rec.event_id = 90001
        AND __rec.code = 'test_order_created'
        AND __rec.category_code = 'test_app_event'
        AND __rec.is_system = false THEN
        RAISE NOTICE '  PASS: Created event code id=%, code="%", is_system=%',
            __rec.event_id, __rec.code, __rec.is_system;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected event code values: id=%, code=%, is_system=%',
            __rec.event_id, __rec.code, __rec.is_system;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Create event code with is_read_only flag
-- ============================================================================
DO $$
DECLARE
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 3: Create event code with is_read_only flag';

    SELECT * INTO __rec
    FROM public.create_event_code(
        'test_ecm', 1, 'test-corr',
        90002, 'test_order_viewed', 'test_app_event',
        'Order Viewed', 'An order was viewed', true
    );

    IF __rec.event_id = 90002 AND __rec.is_read_only = true AND __rec.is_system = false THEN
        RAISE NOTICE '  PASS: Created read-only event code id=%, is_read_only=%, is_system=%',
            __rec.event_id, __rec.is_read_only, __rec.is_system;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected values: id=%, is_read_only=%, is_system=%',
            __rec.event_id, __rec.is_read_only, __rec.is_system;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Event code out of range raises error
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 4: Event code out of range raises error';

    BEGIN
        PERFORM public.create_event_code(
            'test_ecm', 1, 'test-corr',
            99999, 'test_out_of_range', 'test_app_event',
            'Out of Range', 'This should fail'
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31013' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31013 for out-of-range event ID';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 5: Event code with non-existent category raises error
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 5: Event code with non-existent category raises error';

    BEGIN
        PERFORM public.create_event_code(
            'test_ecm', 1, 'test-corr',
            99999, 'test_bad_category', 'nonexistent_category',
            'Bad Category', 'This should fail'
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31014' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31014 for non-existent category';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 6: Create event message template
-- ============================================================================
DO $$
DECLARE
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 6: Create event message template';

    SELECT * INTO __rec
    FROM public.create_event_message(
        'test_ecm', 1, 'test-corr',
        90001, 'Order "{order_number}" was created by {actor}'
    );

    IF __rec.event_id = 90001
        AND __rec.language_code = 'en'
        AND __rec.message_template = 'Order "{order_number}" was created by {actor}' THEN
        RAISE NOTICE '  PASS: Created message template for event_id=%, lang="%"',
            __rec.event_id, __rec.language_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Unexpected message values: event_id=%, lang=%, template=%',
            __rec.event_id, __rec.language_code, __rec.message_template;
    END IF;

    -- Store event_message_id for later tests
    PERFORM set_config('test.event_message_id', __rec.event_message_id::text, false);
END $$;

-- ============================================================================
-- TEST 7: Create event message for non-existent event raises error
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 7: Create event message for non-existent event raises error';

    BEGIN
        PERFORM public.create_event_message(
            'test_ecm', 1, 'test-corr',
            99999, 'This should fail'
        );
        RAISE EXCEPTION '  FAIL: Expected error was not thrown';
    EXCEPTION
        WHEN SQLSTATE '31011' THEN
            RAISE NOTICE '  PASS: Correctly threw error 31011 for non-existent event code';
        WHEN OTHERS THEN
            RAISE EXCEPTION '  FAIL: Got unexpected error: % %', SQLSTATE, SQLERRM;
    END;
END $$;

-- ============================================================================
-- TEST 8: Custom event code works with create_journal_message
-- ============================================================================
DO $$
DECLARE
    __rec record;
    __template text;
BEGIN
    RAISE NOTICE 'TEST 8: Custom event code works with create_journal_message';

    -- First verify the template resolves
    SELECT public.get_event_message_template(90001) INTO __template;

    IF __template IS NULL OR __template = '' THEN
        RAISE EXCEPTION '  FAIL: Event message template not found for event_id 90001';
    END IF;

    -- Create a journal entry using the custom event code
    SELECT * INTO __rec
    FROM public.create_journal_message(
        'test_ecm', 1, 'test-corr',
        90001,
        jsonb_build_object('order', '12345'),
        jsonb_build_object('order_number', 'ORD-12345'),
        1
    );

    IF __rec.event_id = 90001 THEN
        RAISE NOTICE '  PASS: Journal entry created with custom event_id=%, template="%"',
            __rec.event_id, __template;
    ELSE
        RAISE EXCEPTION '  FAIL: Journal entry has wrong event_id: %', __rec.event_id;
    END IF;

    -- Store journal_id for cleanup
    PERFORM set_config('test.journal_id', __rec.journal_id::text, false);
END $$;

-- ============================================================================
-- TEST 9: Custom event code works with create_journal_message by code name
-- ============================================================================
DO $$
DECLARE
    __rec record;
BEGIN
    RAISE NOTICE 'TEST 9: Custom event code works with create_journal_message by code name';

    SELECT * INTO __rec
    FROM public.create_journal_message(
        'test_ecm', 1, 'test-corr',
        'test_order_created',
        jsonb_build_object('order', '12346'),
        jsonb_build_object('order_number', 'ORD-12346'),
        1
    );

    IF __rec.event_id = 90001 THEN
        RAISE NOTICE '  PASS: Journal entry created using event code name, event_id=%', __rec.event_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Journal entry has wrong event_id: %', __rec.event_id;
    END IF;

    -- Store for cleanup
    PERFORM set_config('test.journal_id_2', __rec.journal_id::text, false);
END $$;

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

-- ============================================================================
-- TEST 16: Delete custom event message
-- ============================================================================
DO $$
DECLARE
    __event_message_id integer;
    __count_before int;
    __count_after int;
BEGIN
    RAISE NOTICE 'TEST 16: Delete a custom event message';

    __event_message_id := current_setting('test.event_message_id')::integer;

    SELECT count(*) INTO __count_before
    FROM const.event_message WHERE event_message_id = __event_message_id;

    PERFORM public.delete_event_message('test_ecm', 1, 'test-corr', __event_message_id);

    SELECT count(*) INTO __count_after
    FROM const.event_message WHERE event_message_id = __event_message_id;

    IF __count_before = 1 AND __count_after = 0 THEN
        RAISE NOTICE '  PASS: Deleted event message id=%', __event_message_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Message not deleted (before=%, after=%)', __count_before, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: Delete custom event code cascades to messages
-- ============================================================================
DO $$
DECLARE
    __msg_count_before int;
    __code_count_after int;
    __msg_count_after int;
BEGIN
    RAISE NOTICE 'TEST 17: Delete custom event code cascades to messages';

    -- Re-create a message for event 90002 so we can test cascade
    INSERT INTO const.event_message (created_by, updated_by, event_id, language_code, message_template)
    VALUES ('test_ecm', 'test_ecm', 90002, 'en', 'Order was viewed');

    SELECT count(*) INTO __msg_count_before
    FROM const.event_message WHERE event_id = 90002;

    PERFORM public.delete_event_code('test_ecm', 1, 'test-corr', 90002);

    SELECT count(*) INTO __code_count_after FROM const.event_code WHERE event_id = 90002;
    SELECT count(*) INTO __msg_count_after FROM const.event_message WHERE event_id = 90002;

    IF __code_count_after = 0 AND __msg_count_after = 0 AND __msg_count_before > 0 THEN
        RAISE NOTICE '  PASS: Deleted event code 90002 and cascaded % message(s)', __msg_count_before;
    ELSE
        RAISE EXCEPTION '  FAIL: code_count=%, msg_before=%, msg_after=%',
            __code_count_after, __msg_count_before, __msg_count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 18: Delete remaining custom event code
-- ============================================================================
DO $$
DECLARE
    __count_after int;
BEGIN
    RAISE NOTICE 'TEST 18: Delete remaining custom event code';

    -- Clean up journal entries that reference this event code (created by TEST 8 & 9)
    DELETE FROM journal WHERE event_id = 90001;

    PERFORM public.delete_event_code('test_ecm', 1, 'test-corr', 90001);

    SELECT count(*) INTO __count_after FROM const.event_code WHERE event_id = 90001;

    IF __count_after = 0 THEN
        RAISE NOTICE '  PASS: Deleted event code 90001';
    ELSE
        RAISE EXCEPTION '  FAIL: Event code 90001 still exists';
    END IF;
END $$;

-- ============================================================================
-- TEST 19: Delete empty custom category
-- ============================================================================
DO $$
DECLARE
    __count_after int;
BEGIN
    RAISE NOTICE 'TEST 19: Delete empty custom category';

    PERFORM public.delete_event_category('test_ecm', 1, 'test-corr', 'test_app_event');

    SELECT count(*) INTO __count_after FROM const.event_category WHERE category_code = 'test_app_event';

    IF __count_after = 0 THEN
        RAISE NOTICE '  PASS: Deleted empty category "test_app_event"';
    ELSE
        RAISE EXCEPTION '  FAIL: Category "test_app_event" still exists';
    END IF;
END $$;

-- ============================================================================
-- TEST 20: System events still intact after all tests
-- ============================================================================
DO $$
DECLARE
    __system_count int;
    __system_msg_count int;
BEGIN
    RAISE NOTICE 'TEST 20: System events remain intact';

    SELECT count(*) INTO __system_count FROM const.event_code WHERE is_system = true;
    SELECT count(*) INTO __system_msg_count
    FROM const.event_message em
    JOIN const.event_code ec ON ec.event_id = em.event_id
    WHERE ec.is_system = true;

    IF __system_count > 0 AND __system_msg_count > 0 THEN
        RAISE NOTICE '  PASS: % system event codes and % system messages intact',
            __system_count, __system_msg_count;
    ELSE
        RAISE EXCEPTION '  FAIL: System data missing (codes=%, messages=%)',
            __system_count, __system_msg_count;
    END IF;
END $$;

-- ============================================================================
-- CLEANUP: Remove test data
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Clean up journal entries created by tests
    DELETE FROM journal WHERE created_by = 'test_ecm';

    -- Clean up any leftover test event messages
    DELETE FROM const.event_message WHERE created_by = 'test_ecm';

    -- Clean up any leftover test event codes
    DELETE FROM const.event_code WHERE event_id BETWEEN 90001 AND 90999;

    -- Clean up test category
    DELETE FROM const.event_category WHERE category_code = 'test_app_event';

    RAISE NOTICE 'CLEANUP: Done';
END $$;

-- ============================================================================
-- Summary
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Event Code Management Tests - COMPLETED SUCCESSFULLY';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 20 tests passed:';
    RAISE NOTICE '  1.  Create a custom event category';
    RAISE NOTICE '  2.  Create a custom event code within valid range';
    RAISE NOTICE '  3.  Create event code with is_read_only flag';
    RAISE NOTICE '  4.  Event code out of range raises error';
    RAISE NOTICE '  5.  Event code with non-existent category raises error';
    RAISE NOTICE '  6.  Create event message template';
    RAISE NOTICE '  7.  Create event message for non-existent event raises error';
    RAISE NOTICE '  8.  Custom event code works with create_journal_message';
    RAISE NOTICE '  9.  Custom event code works with create_journal_message by code name';
    RAISE NOTICE '  10. Cannot delete a system event code';
    RAISE NOTICE '  11. Cannot delete a non-existent event code';
    RAISE NOTICE '  12. Cannot delete a system event message';
    RAISE NOTICE '  13. Cannot delete category with system event codes';
    RAISE NOTICE '  14. Cannot delete non-empty category';
    RAISE NOTICE '  15. Cannot delete non-existent category';
    RAISE NOTICE '  16. Delete a custom event message';
    RAISE NOTICE '  17. Delete custom event code cascades to messages';
    RAISE NOTICE '  18. Delete remaining custom event code';
    RAISE NOTICE '  19. Delete empty custom category';
    RAISE NOTICE '  20. System events remain intact';
    RAISE NOTICE '';
END $$;
