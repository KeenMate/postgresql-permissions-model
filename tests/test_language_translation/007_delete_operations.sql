set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 24: Delete translation
-- ============================================================================
DO $$
DECLARE
    __trans_id int;
    __count_before int;
    __count_after int;
BEGIN
    RAISE NOTICE 'TEST 24: Delete translation';

    SELECT translation_id INTO __trans_id
    FROM public.translation
    WHERE language_code = 'en' AND data_group = 'ui_labels' AND data_object_code = 'farewell';

    SELECT count(*) INTO __count_before FROM public.translation WHERE data_group = 'ui_labels';

    PERFORM public.delete_translation('test', 1, 'test-corr-12', __trans_id);

    SELECT count(*) INTO __count_after FROM public.translation WHERE data_group = 'ui_labels';

    IF __count_after = __count_before - 1 THEN
        RAISE NOTICE '  PASS: Translation deleted (% -> %)', __count_before, __count_after;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected % -> %, got %', __count_before, __count_before - 1, __count_after;
    END IF;
END $$;

-- ============================================================================
-- TEST 25: Delete language cascades to translations
-- ============================================================================
DO $$
DECLARE
    __fr_trans_count int;
    __after_count int;
BEGIN
    RAISE NOTICE 'TEST 25: Delete language cascades to translations';

    SELECT count(*) INTO __fr_trans_count
    FROM public.translation WHERE language_code = 'fr';

    PERFORM public.delete_language('test', 1, 'test-corr-13', 'fr');

    SELECT count(*) INTO __after_count
    FROM public.translation WHERE language_code = 'fr';

    IF __after_count = 0 THEN
        RAISE NOTICE '  PASS: French language deleted, % translations cascaded', __fr_trans_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 0 French translations after delete, found %', __after_count;
    END IF;
END $$;
