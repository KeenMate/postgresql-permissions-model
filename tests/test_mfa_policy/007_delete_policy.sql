set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 7: Delete policies — verify cascade behavior
-- ============================================================================
DO $$
DECLARE
    __user1_id         bigint  := current_setting('test.mfapol_user1_id')::bigint;
    __user2_id         bigint  := current_setting('test.mfapol_user2_id')::bigint;
    __user_policy_id   bigint  := current_setting('test.mfapol_user_policy_id')::bigint;
    __group_policy_id  bigint  := current_setting('test.mfapol_group_policy_id')::bigint;
    __tenant_policy_id bigint  := current_setting('test.mfapol_tenant_policy_id')::bigint;
    __global_policy_id bigint  := current_setting('test.mfapol_global_policy_id')::bigint;
    __required         boolean;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 7: Delete policies and verify resolution --';

    -- Current state: global=true, tenant=false, group=true, user=false
    -- user1 gets false (user-level exemption)

    -- Delete user policy → group rule takes effect → user1 gets true
    PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-07a', __user_policy_id);

    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: After deleting user policy, group policy applies (mfa_required=true)';
    ELSE
        RAISE EXCEPTION 'FAIL: Group policy should apply after user policy deleted';
    END IF;

    -- Verify delete event logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.event_type_code = 'mfa_policy_deleted'
          AND (ue.event_data ->> 'mfa_policy_id')::bigint = __user_policy_id
    ) THEN
        RAISE NOTICE 'PASS: mfa_policy_deleted event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_policy_deleted event not found';
    END IF;

    -- Delete group policy → tenant rule takes effect → user1 gets false
    PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-07b', __group_policy_id);

    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: After deleting group policy, tenant policy applies (mfa_required=false)';
    ELSE
        RAISE EXCEPTION 'FAIL: Tenant policy should apply after group policy deleted';
    END IF;

    -- Delete tenant policy → global rule takes effect → user1 gets true
    PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-07c', __tenant_policy_id);

    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: After deleting tenant policy, global policy applies (mfa_required=true)';
    ELSE
        RAISE EXCEPTION 'FAIL: Global policy should apply after tenant policy deleted';
    END IF;

    -- Delete global policy → no match → default false
    PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-07d', __global_policy_id);

    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: After deleting all policies, default is false';
    ELSE
        RAISE EXCEPTION 'FAIL: Default should be false when no policies exist';
    END IF;

    __required := unsecure.is_mfa_required(__user2_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: user2 also gets false with no policies';
    ELSE
        RAISE EXCEPTION 'FAIL: user2 should also get false when no policies exist';
    END IF;
END $$;
