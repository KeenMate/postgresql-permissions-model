set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
