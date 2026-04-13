set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Test framework helpers
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Group Types Tests - Starting';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- SETUP: Clean any leftover test data and create test fixtures
-- ============================================================================
DO $$
DECLARE
    __group_id int;
    __provider_id int;
BEGIN
    RAISE NOTICE 'SETUP: Cleaning leftover test data...';

    DELETE FROM auth.user_group_mapping WHERE provider_code = 'gt_test_prov';
    DELETE FROM auth.user_group_member WHERE created_by = 'gt_test';
    DELETE FROM public.journal WHERE created_by = 'gt_test';
    DELETE FROM auth.user_group WHERE code LIKE 'gt_test_%';
    DELETE FROM auth.provider WHERE code = 'gt_test_prov';

    RAISE NOTICE 'SETUP: Creating test provider for external group mappings...';

    -- Create a test provider that allows group mapping
    SELECT p.__provider_id
    FROM auth.create_provider('gt_test', 1, 'gt-setup', 'gt_test_prov', 'Group Types Test Provider', true,
        _allows_group_mapping := true) p
    INTO __provider_id;

    PERFORM set_config('test.gt_provider_id', __provider_id::text, false);

    RAISE NOTICE 'SETUP: Creating test groups...';

    -- Create a standard internal group for type switching tests
    SELECT g.__user_group_id
    FROM auth.create_user_group('gt_test', 1, 'gt-setup', 'GT Test Internal Group 1') g
    INTO __group_id;
    PERFORM set_config('test.gt_group1_id', __group_id::text, false);

    -- Create a second group for enable/disable tests
    SELECT g.__user_group_id
    FROM auth.create_user_group('gt_test', 1, 'gt-setup', 'GT Test Internal Group 2') g
    INTO __group_id;
    PERFORM set_config('test.gt_group2_id', __group_id::text, false);

    -- Create a third group for lock/unlock tests
    SELECT g.__user_group_id
    FROM auth.create_user_group('gt_test', 1, 'gt-setup', 'GT Test Internal Group 3') g
    INTO __group_id;
    PERFORM set_config('test.gt_group3_id', __group_id::text, false);

    RAISE NOTICE 'SETUP: Done (provider_id=%, group1=%, group2=%, group3=%)',
        __provider_id, current_setting('test.gt_group1_id'),
        current_setting('test.gt_group2_id'), current_setting('test.gt_group3_id');
    RAISE NOTICE '';
END $$;
