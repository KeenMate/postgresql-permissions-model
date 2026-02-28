set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 12: public.search_journal executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 12: public.search_journal executes without error';

    SELECT count(*) INTO __count FROM public.search_journal(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_journal returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 13: auth.search_user_events executes without error
-- ============================================================================
DO $$
DECLARE
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 13: auth.search_user_events executes without error';

    SELECT count(*) INTO __count FROM auth.search_user_events(1, null);

    IF __count >= 0 THEN
        RAISE NOTICE '  PASS: search_user_events returned % results', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected result';
    END IF;
END $$;

-- ============================================================================
-- TEST 14: Pagination works (page_size limits results)
-- ============================================================================
DO $$
DECLARE
    __total bigint;
    __returned_count bigint;
BEGIN
    RAISE NOTICE 'TEST 14: Pagination limits results';

    SELECT count(*), max(r.__total_items)
    INTO __returned_count, __total
    FROM auth.search_permissions(1, null, null, _page_size := 2) r;

    IF __returned_count <= 2 AND __total > __returned_count THEN
        RAISE NOTICE '  PASS: page_size=2 returned % rows, total_items=%', __returned_count, __total;
    ELSIF __returned_count <= 2 THEN
        RAISE NOTICE '  PASS: page_size=2 returned % rows (total_items=%)', __returned_count, __total;
    ELSE
        RAISE EXCEPTION '  FAIL: page_size=2 should return at most 2 rows, got %', __returned_count;
    END IF;
END $$;
