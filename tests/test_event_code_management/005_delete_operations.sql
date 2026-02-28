set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
