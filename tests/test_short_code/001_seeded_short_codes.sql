set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Existing seeded permissions have auto-computed short_code
-- ============================================================================
DO $$
DECLARE
    __total int;
    __with_code int;
BEGIN
    RAISE NOTICE 'TEST 1: Seeded permissions have auto-computed short_code';

    SELECT count(*), count(short_code)
    FROM auth.permission
    INTO __total, __with_code;

    IF __total > 0 AND __total = __with_code THEN
        RAISE NOTICE '  PASS: All % permissions have short_code populated', __total;
    ELSE
        RAISE EXCEPTION '  FAIL: % of % permissions have short_code', __with_code, __total;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Short codes follow hierarchical format (NN.NN...)
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 2: Short codes follow hierarchical format';

    -- All short_codes should match pattern: two-digit groups separated by dots
    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE short_code !~ '^[0-9]{2}(\.[0-9]{2})*$';

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All short_codes match NN.NN... format';
    ELSE
        RAISE EXCEPTION '  FAIL: % short_codes do not match expected format', __bad_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Root permissions have single-segment short_code (e.g., 01)
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 3: Root permissions have single-segment short_code';

    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE nlevel(node_path) = 1
      AND short_code LIKE '%.%';

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All root permissions have single-segment short_code';
    ELSE
        RAISE EXCEPTION '  FAIL: % root permissions have multi-segment short_code', __bad_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Child permissions have depth-matching short_code segments
-- ============================================================================
DO $$
DECLARE
    __bad_count int;
BEGIN
    RAISE NOTICE 'TEST 4: Short code depth matches tree depth';

    -- Number of dot-separated segments should equal nlevel(node_path)
    SELECT count(*) INTO __bad_count
    FROM auth.permission
    WHERE array_length(string_to_array(short_code, '.'), 1) <> nlevel(node_path);

    IF __bad_count = 0 THEN
        RAISE NOTICE '  PASS: All short_code depths match tree depths';
    ELSE
        RAISE EXCEPTION '  FAIL: % permissions have mismatched short_code depth', __bad_count;
    END IF;
END $$;
