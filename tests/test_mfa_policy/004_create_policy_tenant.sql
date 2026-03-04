set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 4: Tenant MFA policy — overrides global
-- ============================================================================
DO $$
DECLARE
    __user1_id  bigint  := current_setting('test.mfapol_user1_id')::bigint;
    __user2_id  bigint  := current_setting('test.mfapol_user2_id')::bigint;
    __result    record;
    __required  boolean;
    __policy_id bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 4: Tenant MFA policy overrides global --';

    -- Create tenant-level policy for tenant 1 with mfa_required=false
    -- This should override the global policy (mfa_required=true) from test 3
    SELECT * INTO __result
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-04', _tenant_id := 1, _mfa_required := false);

    __policy_id := __result.__mfa_policy_id;
    PERFORM set_config('test.mfapol_tenant_policy_id', __policy_id::text, false);

    RAISE NOTICE 'Created tenant policy (id: %, mfa_required=false)', __policy_id;

    -- is_mfa_required should now return false (tenant overrides global)
    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: is_mfa_required returns false (tenant overrides global)';
    ELSE
        RAISE EXCEPTION 'FAIL: Tenant policy (mfa_required=false) should override global (mfa_required=true)';
    END IF;

    -- Delete tenant policy → global should take effect again
    PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-04b', __policy_id);

    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: After deleting tenant policy, global policy takes effect (mfa_required=true)';
    ELSE
        RAISE EXCEPTION 'FAIL: Global policy should apply after tenant policy deleted';
    END IF;

    -- Re-create the tenant policy for subsequent tests
    SELECT * INTO __result
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-04c', _tenant_id := 1, _mfa_required := false);

    PERFORM set_config('test.mfapol_tenant_policy_id', __result.__mfa_policy_id::text, false);
END $$;
