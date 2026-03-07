set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
    WHERE category_code IN ('language_event', 'translation_event', 'language_error');

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
      AND p.proname IN ('raise_37001', 'raise_37002');

    IF __func_count = 2 THEN
        RAISE NOTICE '  PASS: Both error functions exist';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 error functions, found %', __func_count;
    END IF;
END $$;
