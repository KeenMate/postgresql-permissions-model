set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
