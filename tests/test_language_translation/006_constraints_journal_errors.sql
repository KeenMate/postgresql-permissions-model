set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

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
      AND event_id BETWEEN 20001 AND 21999;

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
    RAISE NOTICE 'TEST 22: Error 37001 - language not found on update';

    BEGIN
        PERFORM public.update_language('test', 1, 'test-corr-err1', 'xx_nonexistent');
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent language';
    EXCEPTION
        WHEN SQLSTATE '37001' THEN
            RAISE NOTICE '  PASS: Correctly raised error 37001';
    END;
END $$;

-- ============================================================================
-- TEST 23: Error handling - translation not found
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'TEST 23: Error 37002 - translation not found on update';

    BEGIN
        PERFORM public.update_translation('test', 1, 'test-corr-err2', 999999, 'nonexistent');
        RAISE EXCEPTION '  FAIL: Should have raised exception for nonexistent translation';
    EXCEPTION
        WHEN SQLSTATE '37002' THEN
            RAISE NOTICE '  PASS: Correctly raised error 37002';
    END;
END $$;
