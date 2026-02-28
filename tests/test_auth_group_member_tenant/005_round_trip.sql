set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 11: Re-add and verify round-trip works
-- ============================================================================
DO $$
DECLARE
    __user_id bigint := current_setting('test_agmt.user_id')::bigint;
    __target_id bigint := current_setting('test_agmt.target_id')::bigint;
    __group_id int := current_setting('test_agmt.group_id')::int;
    __member_id bigint;
    __tenant_count int;
BEGIN
    RAISE NOTICE 'TEST 11: Full round-trip - add member, check tenant, remove member';

    -- Add
    SELECT __user_group_member_id INTO __member_id
    FROM auth.create_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    -- Check tenant visible
    SELECT count(*) INTO __tenant_count
    FROM auth.get_user_available_tenants(__user_id, 'test-agmt-corr', __target_id);

    -- Remove
    PERFORM auth.delete_user_group_member('test_agmt', __user_id, 'test-agmt-corr', __group_id, __target_id);

    IF __member_id IS NOT NULL AND __tenant_count >= 1 THEN
        RAISE NOTICE '  PASS: Round-trip complete (member_id=%, tenants=%)', __member_id, __tenant_count;
    ELSE
        RAISE EXCEPTION '  FAIL: Round-trip failed (member_id=%, tenants=%)', __member_id, __tenant_count;
    END IF;
END $$;
