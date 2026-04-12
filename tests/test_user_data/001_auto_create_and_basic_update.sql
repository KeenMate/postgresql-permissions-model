set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: First update auto-creates user_data row
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 1: First update auto-creates user_data row';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    -- No user_data row exists yet
    IF exists (SELECT 1 FROM auth.user_data WHERE user_id = __user_id) THEN
        RAISE EXCEPTION '  FAIL: user_data row should not exist before first update';
    END IF;

    -- First update creates the row
    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-ud-1', __user_id,
        _first_name := 'John')
    INTO __result;

    IF __result.user_data_id IS NOT NULL AND __result.first_name = 'John' THEN
        RAISE NOTICE '  PASS: Row auto-created with first_name=John';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected auto-created row, got %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Name fields use coalesce — null leaves unchanged
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 2: Name fields use coalesce — null leaves unchanged';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    -- Update last_name only, first_name should stay 'John'
    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-ud-2', __user_id,
        _last_name := 'Doe')
    INTO __result;

    IF __result.first_name = 'John' AND __result.last_name = 'Doe' THEN
        RAISE NOTICE '  PASS: first_name preserved, last_name updated';
    ELSE
        RAISE EXCEPTION '  FAIL: first=%, last=%', __result.first_name, __result.last_name;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: All three name fields in one call
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 3: All three name fields in one call';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-ud-3', __user_id,
        _first_name := 'Jane', _middle_name := 'M', _last_name := 'Smith')
    INTO __result;

    IF __result.first_name = 'Jane' AND __result.middle_name = 'M' AND __result.last_name = 'Smith' THEN
        RAISE NOTICE '  PASS: All name fields updated';
    ELSE
        RAISE EXCEPTION '  FAIL: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Default jsonb values are empty objects
-- ============================================================================
DO $$
DECLARE
    __user_id bigint;
    __result auth.user_data;
BEGIN
    RAISE NOTICE 'TEST 4: Default jsonb values are empty objects';
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.user_data WHERE user_id = __user_id INTO __result;

    IF __result.settings = '{}'::jsonb
       AND __result.preferences = '{}'::jsonb
       AND __result.custom_data = '{}'::jsonb THEN
        RAISE NOTICE '  PASS: All jsonb columns default to {}';
    ELSE
        RAISE EXCEPTION '  FAIL: settings=%, preferences=%, custom_data=%',
            __result.settings, __result.preferences, __result.custom_data;
    END IF;
END $$;
