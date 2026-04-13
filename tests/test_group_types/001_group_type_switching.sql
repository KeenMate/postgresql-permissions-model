set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: newly created group is internal (is_external=false)
-- ============================================================================
DO $$
DECLARE
    __is_external boolean;
BEGIN
    RAISE NOTICE 'TEST 1: newly created group is internal';

    SELECT ug.is_external
    FROM auth.user_group ug
    WHERE ug.user_group_id = current_setting('test.gt_group1_id')::int
    INTO __is_external;

    IF __is_external = false THEN
        RAISE NOTICE '  PASS: group is internal (is_external=%)', __is_external;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_external=false, got %', __is_external;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: set_user_group_as_external sets is_external=true
-- ============================================================================
DO $$
DECLARE
    __is_external boolean;
BEGIN
    RAISE NOTICE 'TEST 2: set_user_group_as_external sets is_external=true';

    PERFORM auth.set_user_group_as_external(
        'gt_test', 1, 'gt-ext1',
        current_setting('test.gt_group1_id')::int
    );

    SELECT ug.is_external
    FROM auth.user_group ug
    WHERE ug.user_group_id = current_setting('test.gt_group1_id')::int
    INTO __is_external;

    IF __is_external = true THEN
        RAISE NOTICE '  PASS: group set to external (is_external=%)', __is_external;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_external=true, got %', __is_external;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: set_user_group_as_external removes manual members
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __member_count int;
BEGIN
    RAISE NOTICE 'TEST 3: set_user_group_as_external removes manual members';

    -- create a fresh group, add a manual member, then switch to external
    SELECT g.__user_group_id
    FROM auth.create_user_group('gt_test', 1, 'gt-ext-mem', 'GT Test External Members') g
    INTO __group_id;

    -- add system user (id=1) as manual member
    PERFORM auth.create_user_group_member('gt_test', 1, 'gt-ext-mem', __group_id, 1);

    -- verify member exists
    SELECT count(*)
    FROM auth.user_group_member
    WHERE user_group_id = __group_id AND member_type_code = 'manual'
    INTO __member_count;

    IF __member_count = 0 THEN
        RAISE EXCEPTION '  FAIL: manual member not created';
    END IF;

    -- switch to external (should remove manual members)
    PERFORM auth.set_user_group_as_external('gt_test', 1, 'gt-ext-mem', __group_id);

    SELECT count(*)
    FROM auth.user_group_member
    WHERE user_group_id = __group_id AND member_type_code = 'manual'
    INTO __member_count;

    IF __member_count = 0 THEN
        RAISE NOTICE '  PASS: manual members removed after set_external (count=%)', __member_count;
    ELSE
        RAISE EXCEPTION '  FAIL: manual members still exist (count=%)', __member_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: set_user_group_as_external journals action=set_external
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 4: set_user_group_as_external journals action=set_external';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-ext1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'set_external' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: set_user_group_as_hybrid sets is_external=false (keeps mappings)
-- ============================================================================
DO $$
DECLARE
    __is_external boolean;
BEGIN
    RAISE NOTICE 'TEST 5: set_user_group_as_hybrid sets is_external=false';

    -- group1 is currently external from TEST 2
    PERFORM auth.set_user_group_as_hybrid(
        'gt_test', 1, 'gt-hyb1',
        current_setting('test.gt_group1_id')::int
    );

    SELECT ug.is_external
    FROM auth.user_group ug
    WHERE ug.user_group_id = current_setting('test.gt_group1_id')::int
    INTO __is_external;

    IF __is_external = false THEN
        RAISE NOTICE '  PASS: group set to hybrid (is_external=%)', __is_external;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_external=false for hybrid, got %', __is_external;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: set_user_group_as_hybrid journals action=set_hybrid
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 6: set_user_group_as_hybrid journals action=set_hybrid';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-hyb1'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'set_hybrid' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: set_user_group_as_internal removes non-manual members and mappings
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __is_external boolean;
    __is_synced boolean;
    __mapping_count int;
BEGIN
    RAISE NOTICE 'TEST 7: set_user_group_as_internal removes non-manual members and mappings';

    -- create a group, make it external, add a mapping, then switch back to internal
    SELECT g.__user_group_id
    FROM auth.create_user_group('gt_test', 1, 'gt-int1', 'GT Test Internal Switch') g
    INTO __group_id;

    -- set external first
    PERFORM auth.set_user_group_as_external('gt_test', 1, 'gt-int1', __group_id);

    -- add a mapping
    PERFORM auth.create_user_group_mapping(
        'gt_test', 1, 'gt-int1', __group_id,
        'gt_test_prov', 'ext-obj-1', 'External Object 1'
    );

    -- verify mapping exists
    SELECT count(*)
    FROM auth.user_group_mapping
    WHERE user_group_id = __group_id
    INTO __mapping_count;

    IF __mapping_count = 0 THEN
        RAISE EXCEPTION '  FAIL: mapping not created';
    END IF;

    -- switch to internal
    PERFORM auth.set_user_group_as_internal('gt_test', 1, 'gt-int1', __group_id);

    SELECT ug.is_external, ug.is_synced
    FROM auth.user_group ug
    WHERE ug.user_group_id = __group_id
    INTO __is_external, __is_synced;

    SELECT count(*)
    FROM auth.user_group_mapping
    WHERE user_group_id = __group_id
    INTO __mapping_count;

    IF __is_external = false AND __is_synced = false AND __mapping_count = 0 THEN
        RAISE NOTICE '  PASS: group set to internal (is_external=%, is_synced=%, mappings=%)', __is_external, __is_synced, __mapping_count;
    ELSE
        RAISE EXCEPTION '  FAIL: expected internal state (is_external=%, is_synced=%, mappings=%)', __is_external, __is_synced, __mapping_count;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: set_user_group_as_internal journals action=set_internal
-- ============================================================================
DO $$
DECLARE
    __journal_payload jsonb;
BEGIN
    RAISE NOTICE 'TEST 8: set_user_group_as_internal journals action=set_internal';

    SELECT j.data_payload
    FROM public.journal j
    WHERE j.event_id = 13002
      AND j.created_by = 'gt_test'
      AND j.correlation_id = 'gt-int1'
      AND j.data_payload->>'action' = 'set_internal'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_payload;

    IF __journal_payload IS NOT NULL AND __journal_payload->>'action' = 'set_internal' THEN
        RAISE NOTICE '  PASS: journal correct (payload=%)', __journal_payload;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch (payload=%)', __journal_payload;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: create_external_user_group creates group with mapping in one call
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __is_external boolean;
    __mapping_count int;
    __mapping_provider text;
BEGIN
    RAISE NOTICE 'TEST 9: create_external_user_group creates group with mapping';

    SELECT g.__user_group_id
    FROM auth.create_external_user_group(
        'gt_test', 1, 'gt-cext1',
        'GT Test Created External',
        'gt_test_prov',
        true, true,
        'ext-obj-auto', 'Auto External Object'
    ) g
    INTO __group_id;

    PERFORM set_config('test.gt_ext_group_id', __group_id::text, false);

    IF __group_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: create_external_user_group returned NULL';
    END IF;

    SELECT ug.is_external
    FROM auth.user_group ug
    WHERE ug.user_group_id = __group_id
    INTO __is_external;

    SELECT count(*), min(ugm.provider_code)
    FROM auth.user_group_mapping ugm
    WHERE ugm.user_group_id = __group_id
    INTO __mapping_count, __mapping_provider;

    IF __is_external = true AND __mapping_count = 1 AND __mapping_provider = 'gt_test_prov' THEN
        RAISE NOTICE '  PASS: external group with mapping created (id=%, external=%, mappings=%, provider=%)', __group_id, __is_external, __mapping_count, __mapping_provider;
    ELSE
        RAISE EXCEPTION '  FAIL: mismatch (id=%, external=%, mappings=%, provider=%)', __group_id, __is_external, __mapping_count, __mapping_provider;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: create_external_user_group with mapped_role instead of mapped_object_id
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __mapping_role text;
BEGIN
    RAISE NOTICE 'TEST 10: create_external_user_group with mapped_role';

    SELECT g.__user_group_id
    FROM auth.create_external_user_group(
        'gt_test', 1, 'gt-cext2',
        'GT Test External With Role',
        'gt_test_prov',
        true, true,
        null, null, 'admin_role'
    ) g
    INTO __group_id;

    SELECT ugm.mapped_role
    FROM auth.user_group_mapping ugm
    WHERE ugm.user_group_id = __group_id
    INTO __mapping_role;

    IF __mapping_role = 'admin_role' THEN
        RAISE NOTICE '  PASS: external group with mapped_role (role=%)', __mapping_role;
    ELSE
        RAISE EXCEPTION '  FAIL: mapped_role mismatch (expected=admin_role, got=%)', __mapping_role;
    END IF;
END $$;

-- ============================================================================
-- TEST 11: round-trip: internal -> external -> hybrid -> internal
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __is_external boolean;
    __step text;
BEGIN
    RAISE NOTICE 'TEST 11: round-trip type switching internal->external->hybrid->internal';

    __group_id := current_setting('test.gt_group1_id')::int;

    -- currently hybrid from TEST 5, switch to external
    PERFORM auth.set_user_group_as_external('gt_test', 1, 'gt-rt1', __group_id);
    SELECT ug.is_external FROM auth.user_group ug WHERE ug.user_group_id = __group_id INTO __is_external;
    IF __is_external <> true THEN
        RAISE EXCEPTION '  FAIL: step external (is_external=%)', __is_external;
    END IF;

    -- switch to hybrid
    PERFORM auth.set_user_group_as_hybrid('gt_test', 1, 'gt-rt2', __group_id);
    SELECT ug.is_external FROM auth.user_group ug WHERE ug.user_group_id = __group_id INTO __is_external;
    IF __is_external <> false THEN
        RAISE EXCEPTION '  FAIL: step hybrid (is_external=%)', __is_external;
    END IF;

    -- switch to internal
    PERFORM auth.set_user_group_as_internal('gt_test', 1, 'gt-rt3', __group_id);
    SELECT ug.is_external FROM auth.user_group ug WHERE ug.user_group_id = __group_id INTO __is_external;
    IF __is_external <> false THEN
        RAISE EXCEPTION '  FAIL: step internal (is_external=%)', __is_external;
    END IF;

    RAISE NOTICE '  PASS: round-trip type switching completed';
END $$;
