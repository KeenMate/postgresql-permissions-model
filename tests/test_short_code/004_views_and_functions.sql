set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 10: effective_permissions view uses permission_short_code
-- ============================================================================
DO $$
DECLARE
    __col_exists boolean;
BEGIN
    RAISE NOTICE 'TEST 10: effective_permissions view has permission_short_code column';

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'auth'
          AND table_name = 'effective_permissions'
          AND column_name = 'permission_short_code'
    ) INTO __col_exists;

    IF __col_exists THEN
        RAISE NOTICE '  PASS: permission_short_code column exists in effective_permissions view';
    ELSE
        RAISE EXCEPTION '  FAIL: permission_short_code column not found in effective_permissions view';
    END IF;
END $$;

-- ============================================================================
-- TEST 11: get_permissions_map returns __short_code
-- ============================================================================
DO $$
DECLARE
    __row_count int;
    __null_count int;
BEGIN
    RAISE NOTICE 'TEST 11: get_permissions_map returns __short_code';

    SELECT count(*), count(*) - count(__short_code)
    FROM public.get_permissions_map()
    INTO __row_count, __null_count;

    IF __row_count > 0 AND __null_count = 0 THEN
        RAISE NOTICE '  PASS: get_permissions_map returns % rows, all with __short_code', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: % rows, % with null __short_code', __row_count, __null_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: get_all_permissions returns __short_code
-- ============================================================================
DO $$
DECLARE
    __row_count int;
    __null_count int;
BEGIN
    RAISE NOTICE 'TEST 12: get_all_permissions returns __short_code';

    SELECT count(*), count(*) - count(__short_code)
    FROM unsecure.get_all_permissions('test', 1)
    INTO __row_count, __null_count;

    IF __row_count > 0 AND __null_count = 0 THEN
        RAISE NOTICE '  PASS: get_all_permissions returns % rows, all with __short_code', __row_count;
    ELSE
        RAISE EXCEPTION '  FAIL: % rows, % with null __short_code', __row_count, __null_count;
    END IF;
END $$;
