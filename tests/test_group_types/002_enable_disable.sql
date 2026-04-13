set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 12: disable_user_group sets is_active=false
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_active boolean;
BEGIN
    RAISE NOTICE 'TEST 12: disable_user_group sets is_active=false';

    SELECT r.__user_group_id, r.__is_active
    FROM auth.disable_user_group('gt_test', 1, 'gt-dis1', current_setting('test.gt_group2_id')::int) r
    INTO __result_id, __result_active;

    IF __result_id IS NOT NULL AND __result_active = false THEN
        RAISE NOTICE '  PASS: group disabled (id=%, is_active=%)', __result_id, __result_active;
    ELSE
        RAISE EXCEPTION '  FAIL: disable mismatch (id=%, is_active=%)', __result_id, __result_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 13: disable_user_group journals action=disabled
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 13: disable_user_group journals action=disabled';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-dis1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'disabled' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 14: enable_user_group sets is_active=true
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_active boolean;
BEGIN
    RAISE NOTICE 'TEST 14: enable_user_group sets is_active=true';

    SELECT r.__user_group_id, r.__is_active
    FROM auth.enable_user_group('gt_test', 1, 'gt-ena1', current_setting('test.gt_group2_id')::int) r
    INTO __result_id, __result_active;

    IF __result_id IS NOT NULL AND __result_active = true THEN
        RAISE NOTICE '  PASS: group enabled (id=%, is_active=%)', __result_id, __result_active;
    ELSE
        RAISE EXCEPTION '  FAIL: enable mismatch (id=%, is_active=%)', __result_id, __result_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 15: enable_user_group journals action=enabled
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 15: enable_user_group journals action=enabled';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-ena1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'enabled' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 16: lock_user_group sets is_assignable=false
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_assignable boolean;
BEGIN
    RAISE NOTICE 'TEST 16: lock_user_group sets is_assignable=false';

    SELECT r.__user_group_id, r.__is_assignable
    FROM auth.lock_user_group('gt_test', 1, 'gt-lock1', current_setting('test.gt_group3_id')::int) r
    INTO __result_id, __result_assignable;

    IF __result_id IS NOT NULL AND __result_assignable = false THEN
        RAISE NOTICE '  PASS: group locked (id=%, is_assignable=%)', __result_id, __result_assignable;
    ELSE
        RAISE EXCEPTION '  FAIL: lock mismatch (id=%, is_assignable=%)', __result_id, __result_assignable;
    END IF;
END $$;

-- ============================================================================
-- TEST 17: lock_user_group journals action=locked
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 17: lock_user_group journals action=locked';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-lock1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'locked' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 18: unlock_user_group sets is_assignable=true
-- ============================================================================
DO $$
DECLARE
    __result_id int;
    __result_assignable boolean;
BEGIN
    RAISE NOTICE 'TEST 18: unlock_user_group sets is_assignable=true';

    SELECT r.__user_group_id, r.__is_assignable
    FROM auth.unlock_user_group('gt_test', 1, 'gt-unlock1', current_setting('test.gt_group3_id')::int) r
    INTO __result_id, __result_assignable;

    IF __result_id IS NOT NULL AND __result_assignable = true THEN
        RAISE NOTICE '  PASS: group unlocked (id=%, is_assignable=%)', __result_id, __result_assignable;
    ELSE
        RAISE EXCEPTION '  FAIL: unlock mismatch (id=%, is_assignable=%)', __result_id, __result_assignable;
    END IF;
END $$;

-- ============================================================================
-- TEST 19: unlock_user_group journals action=unlocked
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 19: unlock_user_group journals action=unlocked';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-unlock1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'unlocked' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 20: disable then lock preserves both states independently
-- ============================================================================
DO $$
DECLARE
    __is_active boolean;
    __is_assignable boolean;
BEGIN
    RAISE NOTICE 'TEST 20: disable and lock are independent flags';

    -- disable group3
    PERFORM auth.disable_user_group('gt_test', 1, 'gt-combo1', current_setting('test.gt_group3_id')::int);
    -- lock group3
    PERFORM auth.lock_user_group('gt_test', 1, 'gt-combo2', current_setting('test.gt_group3_id')::int);

    SELECT ug.is_active, ug.is_assignable
    FROM auth.user_group ug
    WHERE ug.user_group_id = current_setting('test.gt_group3_id')::int
    INTO __is_active, __is_assignable;

    IF __is_active = false AND __is_assignable = false THEN
        RAISE NOTICE '  PASS: both disabled and locked (is_active=%, is_assignable=%)', __is_active, __is_assignable;
    ELSE
        RAISE EXCEPTION '  FAIL: state mismatch (is_active=%, is_assignable=%)', __is_active, __is_assignable;
    END IF;

    -- enable restores is_active but keeps locked
    PERFORM auth.enable_user_group('gt_test', 1, 'gt-combo3', current_setting('test.gt_group3_id')::int);

    SELECT ug.is_active, ug.is_assignable
    FROM auth.user_group ug
    WHERE ug.user_group_id = current_setting('test.gt_group3_id')::int
    INTO __is_active, __is_assignable;

    IF __is_active = true AND __is_assignable = false THEN
        RAISE NOTICE '  PASS: enabled but still locked (is_active=%, is_assignable=%)', __is_active, __is_assignable;
    ELSE
        RAISE EXCEPTION '  FAIL: state mismatch after enable (is_active=%, is_assignable=%)', __is_active, __is_assignable;
    END IF;
END $$;
