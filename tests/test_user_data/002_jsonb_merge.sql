set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: Settings — initial merge into empty object
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 1: Settings — initial merge into empty object';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-1', __user_id,
        _settings := '{"locale": "en", "timezone": "UTC"}'::jsonb)
    INTO __result;

    IF __result.__settings = '{"locale": "en", "timezone": "UTC"}'::jsonb THEN
        RAISE NOTICE '  PASS: Settings merged: %', __result.__settings;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected {"locale":"en","timezone":"UTC"}, got %', __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Settings — partial update preserves existing keys
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 2: Settings — partial update preserves existing keys';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    -- Change locale only, timezone should stay
    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-2', __user_id,
        _settings := '{"locale": "cs"}'::jsonb)
    INTO __result;

    IF __result.__settings->>'locale' = 'cs' AND __result.__settings->>'timezone' = 'UTC' THEN
        RAISE NOTICE '  PASS: locale changed, timezone preserved: %', __result.__settings;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected locale=cs + timezone=UTC, got %', __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: Settings — add new key alongside existing
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
    __key_count integer;
BEGIN
    RAISE NOTICE 'TEST 3: Settings — add new key alongside existing';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-3', __user_id,
        _settings := '{"notifications": true}'::jsonb)
    INTO __result;

    SELECT count(*) FROM jsonb_object_keys(__result.__settings) INTO __key_count;

    IF __key_count = 3 AND (__result.__settings->>'notifications')::boolean = true THEN
        RAISE NOTICE '  PASS: 3 keys total, notifications added: %', __result.__settings;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 3 keys with notifications, got %', __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: Remove key by passing null value
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 4: Remove key by passing null value';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    -- Remove timezone key
    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-4', __user_id,
        _settings := '{"timezone": null}'::jsonb)
    INTO __result;

    IF NOT (__result.__settings ? 'timezone')
       AND __result.__settings ? 'locale'
       AND __result.__settings ? 'notifications' THEN
        RAISE NOTICE '  PASS: timezone removed, others preserved: %', __result.__settings;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected timezone gone, got %', __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: Preferences — independent from settings
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 5: Preferences — independent from settings';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-5', __user_id,
        _preferences := '{"theme": "dark", "sidebar_collapsed": true}'::jsonb)
    INTO __result;

    -- Settings should be unchanged, preferences updated
    IF __result.__preferences->>'theme' = 'dark'
       AND __result.__settings ? 'locale' THEN
        RAISE NOTICE '  PASS: Preferences set without affecting settings';
    ELSE
        RAISE EXCEPTION '  FAIL: prefs=%, settings=%', __result.__preferences, __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: Custom data — independent from both
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 6: Custom data — independent from both';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_1' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-6', __user_id,
        _custom_data := '{"employee_number": "E-1234", "department": "engineering"}'::jsonb)
    INTO __result;

    IF __result.__custom_data->>'employee_number' = 'E-1234'
       AND __result.__preferences->>'theme' = 'dark'
       AND __result.__settings ? 'locale' THEN
        RAISE NOTICE '  PASS: Custom data set, settings + preferences unchanged';
    ELSE
        RAISE EXCEPTION '  FAIL: custom=%, prefs=%, settings=%',
            __result.__custom_data, __result.__preferences, __result.__settings;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: All three jsonb columns + name in one call
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 7: All three jsonb columns + name in one call';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_2' INTO __user_id;

    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-7', __user_id,
        _first_name  := 'Alice',
        _settings    := '{"locale": "de"}'::jsonb,
        _preferences := '{"items_per_page": 50}'::jsonb,
        _custom_data := '{"cost_center": "CC-100"}'::jsonb)
    INTO __result;

    IF __result.__first_name = 'Alice'
       AND __result.__settings->>'locale' = 'de'
       AND (__result.__preferences->>'items_per_page')::integer = 50
       AND __result.__custom_data->>'cost_center' = 'CC-100' THEN
        RAISE NOTICE '  PASS: All fields updated in one call';
    ELSE
        RAISE EXCEPTION '  FAIL: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: Null jsonb parameter leaves column unchanged
-- ============================================================================
DO $$
DECLARE
    __admin_id bigint;
    __user_id bigint;
    __result record;
BEGIN
    RAISE NOTICE 'TEST 8: Null jsonb parameter leaves column unchanged';
    SELECT val FROM _ud_test_data WHERE key = 'admin_id' INTO __admin_id;
    SELECT val FROM _ud_test_data WHERE key = 'user_id_2' INTO __user_id;

    -- Update only first_name, all jsonb should stay
    SELECT * FROM auth.update_user_data('test', __admin_id, 'test-merge-8', __user_id,
        _first_name := 'Bob')
    INTO __result;

    IF __result.__first_name = 'Bob'
       AND __result.__settings->>'locale' = 'de'
       AND (__result.__preferences->>'items_per_page')::integer = 50
       AND __result.__custom_data->>'cost_center' = 'CC-100' THEN
        RAISE NOTICE '  PASS: Name changed, all jsonb preserved';
    ELSE
        RAISE EXCEPTION '  FAIL: %', __result;
    END IF;
END $$;
