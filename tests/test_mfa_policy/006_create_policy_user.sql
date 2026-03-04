set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 6: User MFA policy — user exemption overrides group rule
-- ============================================================================
DO $$
DECLARE
    __user1_id  bigint := current_setting('test.mfapol_user1_id')::bigint;
    __result    record;
    __required  boolean;
    __policy_id bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 6: User-level policy overrides group --';

    -- Current state: global=true, tenant=false, group=true
    -- user1 is in the group so currently gets mfa_required=true
    -- Create user-level exemption: mfa_required=false for user1
    SELECT * INTO __result
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-06', _target_user_id := __user1_id, _mfa_required := false);

    __policy_id := __result.__mfa_policy_id;
    PERFORM set_config('test.mfapol_user_policy_id', __policy_id::text, false);

    RAISE NOTICE 'Created user policy (id: %, user_id: %, mfa_required=false)', __policy_id, __user1_id;

    -- user1 should now get mfa_required=false (user overrides group)
    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: User policy (mfa_required=false) overrides group policy (mfa_required=true)';
    ELSE
        RAISE EXCEPTION 'FAIL: User-level exemption should override group policy';
    END IF;

    -- Also test auth.is_mfa_required (permission-checked wrapper)
    __required := auth.is_mfa_required(1, 'test-corr-mfapol-06b', __user1_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: auth.is_mfa_required also returns false (permission-checked wrapper works)';
    ELSE
        RAISE EXCEPTION 'FAIL: auth.is_mfa_required should match unsecure.is_mfa_required';
    END IF;
END $$;
