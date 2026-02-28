set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 5: Create language with permission check
-- ============================================================================
DO $$
DECLARE
    __lang record;
BEGIN
    RAISE NOTICE 'TEST 5: Create a new language (German)';

    SELECT * INTO __lang
    FROM public.create_language('test', 1, 'test-corr-1', 'de', 'Deutsch',
        _is_frontend_language := true, _is_backend_language := true,
        _frontend_logical_order := 2, _backend_logical_order := 2);

    IF __lang.code = 'de' AND __lang.value = 'Deutsch' AND __lang.is_frontend_language = true THEN
        RAISE NOTICE '  PASS: German language created (code=%, value=%)', __lang.code, __lang.value;
    ELSE
        RAISE EXCEPTION '  FAIL: Language not created correctly';
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Create language and verify default flag enforcement
-- ============================================================================
DO $$
DECLARE
    __lang record;
    __en_default boolean;
BEGIN
    RAISE NOTICE 'TEST 6: Default flag enforcement - new default unsets previous';

    -- Create French as new default frontend
    SELECT * INTO __lang
    FROM public.create_language('test', 1, 'test-corr-2', 'fr', 'Français',
        _is_frontend_language := true, _is_default_frontend := true,
        _frontend_logical_order := 3);

    -- Check that English is no longer default frontend
    SELECT is_default_frontend INTO __en_default
    FROM const.language WHERE code = 'en';

    IF __lang.is_default_frontend = true AND __en_default = false THEN
        RAISE NOTICE '  PASS: French is new default, English unset';
    ELSE
        RAISE EXCEPTION '  FAIL: Default enforcement failed (fr=%, en=%)', __lang.is_default_frontend, __en_default;
    END IF;

    -- Restore English as default frontend
    PERFORM public.update_language('test', 1, 'test-corr-2b', 'en', _is_default_frontend := true);
END $$;

-- ============================================================================
-- TEST 7: Update language
-- ============================================================================
DO $$
DECLARE
    __lang record;
BEGIN
    RAISE NOTICE 'TEST 7: Update language value';

    SELECT * INTO __lang
    FROM public.update_language('test', 1, 'test-corr-3', 'de', _value := 'German');

    IF __lang.value = 'German' THEN
        RAISE NOTICE '  PASS: Language value updated to "%"', __lang.value;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "German", got "%"', __lang.value;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: Get language
-- ============================================================================
DO $$
DECLARE
    __lang record;
BEGIN
    RAISE NOTICE 'TEST 8: Get single language';

    SELECT * INTO __lang FROM public.get_language('de');

    IF __lang.code = 'de' AND __lang.value = 'German' THEN
        RAISE NOTICE '  PASS: Got language (code=%, value=%)', __lang.code, __lang.value;
    ELSE
        RAISE EXCEPTION '  FAIL: Language not found or wrong values';
    END IF;
END $$;

-- ============================================================================
-- TEST 9: Get languages with filter
-- ============================================================================
DO $$
DECLARE
    __count int;
BEGIN
    RAISE NOTICE 'TEST 9: Get frontend languages';

    SELECT count(*) INTO __count
    FROM public.get_languages(_is_frontend := true);

    IF __count >= 2 THEN
        RAISE NOTICE '  PASS: Found % frontend languages', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 2 frontend languages, found %', __count;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: Get frontend languages ordered
-- ============================================================================
DO $$
DECLARE
    __first_code text;
BEGIN
    RAISE NOTICE 'TEST 10: Get frontend languages ordered by logical_order';

    SELECT __code INTO __first_code
    FROM public.get_frontend_languages()
    LIMIT 1;

    IF __first_code IS NOT NULL THEN
        RAISE NOTICE '  PASS: First frontend language is "%"', __first_code;
    ELSE
        RAISE EXCEPTION '  FAIL: No frontend languages found';
    END IF;
END $$;

-- ============================================================================
-- TEST 11: Get default language
-- ============================================================================
DO $$
DECLARE
    __lang_code text;
BEGIN
    RAISE NOTICE 'TEST 11: Get default frontend language';

    SELECT __code INTO __lang_code
    FROM public.get_default_language(_is_frontend := true);

    IF __lang_code = 'en' THEN
        RAISE NOTICE '  PASS: Default frontend language is "%"', __lang_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "en", got "%"', __lang_code;
    END IF;
END $$;
