set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 11: Refactored owner functions (create_owner)
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __group_id int;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 11: Refactored create_owner function';

    SELECT user_id INTO __target_user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';

    -- Create owner (system user_id=1 is allowed)
    SELECT co.__owner_id INTO __owner_id
    FROM auth.create_owner('test', 1, null, __target_user_id, __group_id, 1) co;

    IF __owner_id IS NOT NULL AND EXISTS (SELECT 1 FROM auth.owner WHERE owner_id = __owner_id) THEN
        RAISE NOTICE '  PASS: create_owner worked (owner_id=%)', __owner_id;
    ELSE
        RAISE EXCEPTION '  FAIL: create_owner failed';
    END IF;

    -- Store for cleanup in next test
    PERFORM set_config('test.owner_id', __owner_id::text, false);
END $$;

-- ============================================================================
-- TEST 12: Refactored owner functions (delete_owner)
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __group_id int;
    __owner_id bigint;
BEGIN
    RAISE NOTICE 'TEST 12: Refactored delete_owner function';

    SELECT user_id INTO __target_user_id FROM auth.user_info WHERE username = 'cache_test_user';
    SELECT user_group_id INTO __group_id FROM auth.user_group WHERE code = 'cache_test_group';
    __owner_id := current_setting('test.owner_id')::bigint;

    -- Delete owner
    PERFORM auth.delete_owner('test', 1, null, __target_user_id, __group_id, 1);

    IF NOT EXISTS (SELECT 1 FROM auth.owner WHERE owner_id = __owner_id) THEN
        RAISE NOTICE '  PASS: delete_owner worked (owner removed)';
    ELSE
        RAISE EXCEPTION '  FAIL: delete_owner failed (owner still exists)';
    END IF;
END $$;
