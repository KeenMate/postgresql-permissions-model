set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 15: get_group_translations returns jsonb
-- ============================================================================
DO $$
DECLARE
    __result jsonb;
BEGIN
    RAISE NOTICE 'TEST 15: get_group_translations returns jsonb aggregation';

    -- Add another translation in same group
    PERFORM public.create_translation('test', 1, 'test-corr-7', 'en', 'ui_labels', 'Goodbye',
        _data_object_code := 'farewell');

    SELECT public.get_group_translations('en', 'ui_labels') INTO __result;

    IF __result ? 'greeting' AND __result ? 'farewell' THEN
        RAISE NOTICE '  PASS: jsonb contains both keys: %', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected keys greeting and farewell, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: search_translations with text filter
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 16: Search translations with text filter';

    SELECT __total_items INTO __count
    FROM public.search_translations(1, 'test-corr-8', 'en', 'hello')
    LIMIT 1;

    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Found % results for "hello"', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 1 result for "hello", got %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: search_translations with group filter
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 17: Search translations with group filter';

    SELECT __total_items INTO __count
    FROM public.search_translations(1, 'test-corr-9', _data_group := 'ui_labels')
    LIMIT 1;

    IF __count >= 2 THEN
        RAISE NOTICE '  PASS: Found % results in ui_labels group', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 2 results, got %', __count;
    END IF;
END $$;
