set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 5: Group MFA policy — member gets group result, non-member gets tenant/global
-- ============================================================================
DO $$
DECLARE
    __user1_id  bigint  := current_setting('test.mfapol_user1_id')::bigint;
    __user2_id  bigint  := current_setting('test.mfapol_user2_id')::bigint;
    __group_id  integer := current_setting('test.mfapol_group_id')::integer;
    __result    record;
    __required  boolean;
    __policy_id bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 5: Group MFA policy --';

    -- Current state: global=true, tenant=false
    -- Create group policy: mfa_required=true for the test group
    SELECT * INTO __result
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-05', _user_group_id := __group_id, _mfa_required := true);

    __policy_id := __result.__mfa_policy_id;
    PERFORM set_config('test.mfapol_group_policy_id', __policy_id::text, false);

    RAISE NOTICE 'Created group policy (id: %, group_id: %, mfa_required=true)', __policy_id, __group_id;

    -- user1 is in the group → group policy applies → mfa_required=true
    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: user1 (group member) gets mfa_required=true from group policy';
    ELSE
        RAISE EXCEPTION 'FAIL: user1 should get mfa_required=true from group policy';
    END IF;

    -- user2 is NOT in the group → falls through to tenant policy → mfa_required=false
    __required := unsecure.is_mfa_required(__user2_id, 1);
    IF NOT __required THEN
        RAISE NOTICE 'PASS: user2 (non-member) gets mfa_required=false from tenant policy';
    ELSE
        RAISE EXCEPTION 'FAIL: user2 should get mfa_required=false from tenant policy (not in group)';
    END IF;
END $$;
