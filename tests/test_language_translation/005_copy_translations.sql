set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 18: Copy translations (insert only, no overwrite)
-- ============================================================================
DO $$
DECLARE
    __inserted bigint;
    __updated bigint;
    __de_count int;
BEGIN
    RAISE NOTICE 'TEST 18: Copy translations from en to de (no overwrite)';

    SELECT __count INTO __inserted
    FROM public.copy_translations('test', 1, 'test-corr-10', 'en', 'de',
        _data_group := 'ui_labels')
    WHERE __operation = 'inserted';

    SELECT __count INTO __updated
    FROM public.copy_translations('test', 1, 'test-corr-10b', 'en', 'de',
        _data_group := 'ui_labels')
    WHERE __operation = 'updated';

    SELECT count(*) INTO __de_count
    FROM public.translation
    WHERE language_code = 'de' AND data_group = 'ui_labels';

    IF __inserted >= 2 AND __updated = 0 AND __de_count >= 2 THEN
        RAISE NOTICE '  PASS: Copied % translations, 0 updated, % total in de', __inserted, __de_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 2 inserts and 0 updates, got ins=% upd=% total=%', __inserted, __updated, __de_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 19: Copy translations with overwrite
-- ============================================================================
DO $$
DECLARE
    __updated bigint;
    __de_value text;
BEGIN
    RAISE NOTICE 'TEST 19: Copy translations with overwrite';

    SELECT __count INTO __updated
    FROM public.copy_translations('test', 1, 'test-corr-11', 'en', 'de',
        _overwrite := true, _data_group := 'ui_labels')
    WHERE __operation = 'updated';

    -- Verify value was overwritten with English value
    SELECT value INTO __de_value
    FROM public.translation
    WHERE language_code = 'de' AND data_group = 'ui_labels' AND data_object_code = 'greeting';

    IF __updated >= 2 AND __de_value = 'Hello Universe' THEN
        RAISE NOTICE '  PASS: % translations overwritten, greeting="%"', __updated, __de_value;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 2 updates and "Hello Universe", got upd=% val="%"', __updated, __de_value;
    END IF;
END $$;
