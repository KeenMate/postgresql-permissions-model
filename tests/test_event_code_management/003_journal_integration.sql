set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
    FROM public.create_journal_message_by_code(
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
