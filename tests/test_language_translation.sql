/*
 * Automated Tests: Language & Translation Management
 * ===================================================
 *
 * Tests for language and translation functionality:
 * - Language CRUD operations
 * - Default flag enforcement (only one default per category)
 * - Translation CRUD operations
 * - Translation trigger verification (ua_search_data, ts_search_data)
 * - Copy translations with/without overwrite
 * - get_group_translations jsonb aggregation
 * - search_translations filtering
 * - Event_message FK enforcement
 * - Journal entries for operations
 * - Error handling (not found cases)
 *
 * Run with: ./exec-sql.sh -f tests/test_language_translation.sql
 *
 * Expected output: All tests should show PASS. Any FAIL will raise an exception.
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework header
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Language & Translation Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Ensure system admin user exists for permission checks
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
BEGIN
    RAISE NOTICE 'SETUP: Preparing test environment...';

    -- Use system user (user_id=1) which has system_admin perm set
    SELECT user_id INTO __test_user_id FROM auth.user_info WHERE user_id = 1;

    IF __test_user_id IS NULL THEN
        RAISE EXCEPTION 'SETUP FAILED: System user (id=1) not found. Run seed data first.';
    END IF;

    RAISE NOTICE 'SETUP: Using system user_id=% for permission checks', __test_user_id;
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 1: Tables exist
-- ============================================================================
DO $$
DECLARE
    __table_count int;
BEGIN
    RAISE NOTICE 'TEST 1: Verify language and translation tables exist';

    SELECT count(*) INTO __table_count
    FROM information_schema.tables
    WHERE (table_schema = 'const' AND table_name = 'language')
       OR (table_schema = 'public' AND table_name = 'translation');

    IF __table_count = 2 THEN
        RAISE NOTICE '  PASS: Both tables exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 tables, found %', __table_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Default 'en' language was seeded
-- ============================================================================
DO $$
DECLARE
    __lang_count int;
BEGIN
    RAISE NOTICE 'TEST 2: Verify default English language was seeded';

    SELECT count(*) INTO __lang_count
    FROM const.language
    WHERE code = 'en' AND value = 'English'
      AND is_default_frontend = true
      AND is_default_backend = true
      AND is_default_communication = true;

    IF __lang_count = 1 THEN
        RAISE NOTICE '  PASS: English language exists with all defaults set';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 1 English language with defaults, found %', __lang_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Event categories and codes exist
-- ============================================================================
DO $$
DECLARE
    __category_count int;
    __event_count int;
BEGIN
    RAISE NOTICE 'TEST 3: Verify event categories and codes exist';

    SELECT count(*) INTO __category_count
    FROM const.event_category
    WHERE category_code IN ('language_event', 'translation_event', 'language_error');

    SELECT count(*) INTO __event_count
    FROM const.event_code
    WHERE event_id BETWEEN 17001 AND 18999
       OR event_id BETWEEN 35001 AND 35999;

    IF __category_count = 3 AND __event_count = 9 THEN
        RAISE NOTICE '  PASS: 3 categories and 9 event codes exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 categories and 9 events, found % categories and % events', __category_count, __event_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Error functions exist
-- ============================================================================
DO $$
DECLARE
    __func_count int;
BEGIN
    RAISE NOTICE 'TEST 4: Verify error functions exist';

    SELECT count(*) INTO __func_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'error'
      AND p.proname IN ('raise_35001', 'raise_35002');

    IF __func_count = 2 THEN
        RAISE NOTICE '  PASS: Both error functions exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 error functions, found %', __func_count;
    END IF;
END $$;

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

-- ============================================================================
-- TEST 12: Create translation and verify trigger
-- ============================================================================
DO $$
DECLARE
    __trans record;
BEGIN
    RAISE NOTICE 'TEST 12: Create translation - trigger fills search fields';

    SELECT * INTO __trans
    FROM public.create_translation('test', 1, 'test-corr-4', 'en', 'ui_labels', 'Hello World',
        _data_object_code := 'greeting');

    IF __trans.ua_search_data IS NOT NULL AND __trans.ts_search_data IS NOT NULL THEN
        RAISE NOTICE '  PASS: Translation created, ua_search_data="%", ts_search_data set',
            __trans.ua_search_data;
    ELSE
        RAISE EXCEPTION '  FAIL: Trigger did not populate search fields';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: Create translation with accent - verify normalize_text
-- ============================================================================
DO $$
DECLARE
    __trans record;
BEGIN
    RAISE NOTICE 'TEST 13: Accent-insensitive search data via normalize_text';

    SELECT * INTO __trans
    FROM public.create_translation('test', 1, 'test-corr-5', 'fr', 'ui_labels', 'Héllo Wörld',
        _data_object_code := 'greeting');

    IF __trans.ua_search_data = 'hello world' THEN
        RAISE NOTICE '  PASS: Accents removed in ua_search_data="%"', __trans.ua_search_data;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "hello world", got "%"', __trans.ua_search_data;
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

    IF __trans.value = 'Hello Universe' THEN
        RAISE NOTICE '  PASS: Translation updated to "%"', __trans.value;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected "Hello Universe", got "%"', __trans.value;
    END IF;
END $$;

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

-- ============================================================================
-- TEST 20: event_message FK enforcement
-- ============================================================================
DO $$
DECLARE
    __fk_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 20: event_message FK to const.language enforced';

    SELECT exists(
        SELECT 1
        FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_event_message_language'
          AND table_schema = 'const'
          AND table_name = 'event_message'
    ) INTO __fk_exists;

    IF __fk_exists THEN
        RAISE NOTICE '  PASS: FK constraint fk_event_message_language exists';
    ELSE
        RAISE EXCEPTION '  FAIL: FK constraint not found';
    END IF;
END $$;

-- ============================================================================
-- TEST 21: Journal entries were created for operations
-- ============================================================================
DO $$
DECLARE
    __journal_count int;
BEGIN
    RAISE NOTICE 'TEST 21: Journal entries created for language/translation operations';

    SELECT count(*) INTO __journal_count
    FROM journal
    WHERE correlation_id LIKE 'test-corr-%'
      AND event_id BETWEEN 17001 AND 18999;

    IF __journal_count >= 5 THEN
        RAISE NOTICE '  PASS: % journal entries found', __journal_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected >= 5 journal entries, found %', __journal_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 22: Error handling - language not found
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 22: Error 35001 - language not found on update';

    BEGIN
        PERFORM public.update_language('test', 1, 'test-corr-err1', 'xx_nonexistent');
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent language';
    EXCEPTION
        WHEN SQLSTATE '35001' THEN
            RAISE NOTICE '  PASS: Correctly raised error 35001';
    END;
END $$;

-- ============================================================================
-- TEST 23: Error handling - translation not found
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 23: Error 35002 - translation not found on update';

    BEGIN
        PERFORM public.update_translation('test', 1, 'test-corr-err2', 999999, 'nonexistent');
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent translation';
    EXCEPTION
        WHEN SQLSTATE '35002' THEN
            RAISE NOTICE '  PASS: Correctly raised error 35002';
    END;
END $$;

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

-- ============================================================================
-- CLEANUP
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'CLEANUP: Removing test data...';

    -- Delete test translations
    DELETE FROM public.translation WHERE data_group = 'ui_labels';

    -- Delete test languages (except 'en')
    DELETE FROM const.language WHERE code NOT IN ('en');

    -- Clean up test journal entries
    DELETE FROM journal WHERE correlation_id LIKE 'test-corr-%';

    RAISE NOTICE 'CLEANUP: Done';
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Language & Translation Tests - Complete';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;
