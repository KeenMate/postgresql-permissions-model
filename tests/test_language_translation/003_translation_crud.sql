set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 12: Create translation and verify trigger
-- ============================================================================
DO $$
DECLARE
    __tid bigint;
    __nrm text;
    __ts tsvector;
BEGIN
    RAISE NOTICE 'TEST 12: Create translation - trigger fills search fields';

    SELECT __translation_id INTO __tid
    FROM public.create_translation('test', 1, 'test-corr-4', 'en', 'ui_labels', 'Hello World',
        _data_object_code := 'greeting');

    SELECT nrm_search_data, ts_search_data INTO __nrm, __ts
    FROM public.translation
    WHERE translation_id = __tid;

    IF __nrm IS NOT NULL AND __ts IS NOT NULL THEN
        RAISE NOTICE '  PASS: Translation created, nrm_search_data="%", ts_search_data set',
            __nrm;
    ELSE
        RAISE EXCEPTION '  FAIL: Trigger did not populate search fields';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: Create translation with accent - verify normalize_text
-- ============================================================================
DO $$
DECLARE
    __tid bigint;
    __nrm text;
BEGIN
    RAISE NOTICE 'TEST 13: Accent-insensitive search data via normalize_text';

    SELECT __translation_id INTO __tid
    FROM public.create_translation('test', 1, 'test-corr-5', 'fr', 'ui_labels', 'Héllo Wörld',
        _data_object_code := 'greeting');

    SELECT nrm_search_data INTO __nrm
    FROM public.translation
    WHERE translation_id = __tid;

    IF __nrm = 'hello world' THEN
        RAISE NOTICE '  PASS: Accents removed in nrm_search_data="%"', __nrm;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "hello world", got "%"', __nrm;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: Update translation
-- ============================================================================
DO $$
DECLARE
    __trans record;
    __trans_id int;
BEGIN
    RAISE NOTICE 'TEST 14: Update translation value';

    SELECT translation_id INTO __trans_id
    FROM public.translation
    WHERE language_code = 'en' AND data_group = 'ui_labels' AND data_object_code = 'greeting';

    SELECT * INTO __trans
    FROM public.update_translation('test', 1, 'test-corr-6', __trans_id, 'Hello Universe');

    IF __trans.__value = 'Hello Universe' THEN
        RAISE NOTICE '  PASS: Translation updated to "%"', __trans.__value;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "Hello Universe", got "%"', __trans.__value;
    END IF;
END $$;
