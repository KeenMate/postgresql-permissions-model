set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 3: Global MFA policy — is_mfa_required returns true for any user
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
    RAISE NOTICE '-- Test 3: Global MFA policy --';

    -- Create global policy (all scope params null, mfa_required=true)
    SELECT * INTO __result
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-03');

    __policy_id := __result.__mfa_policy_id;

    IF __policy_id IS NOT NULL THEN
        RAISE NOTICE 'PASS: Global MFA policy created (id: %)', __policy_id;
    ELSE
        RAISE EXCEPTION 'FAIL: create_mfa_policy should return mfa_policy_id';
    END IF;

    PERFORM set_config('test.mfapol_global_policy_id', __policy_id::text, false);

    -- is_mfa_required should return true for user1
    __required := unsecure.is_mfa_required(__user1_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: is_mfa_required returns true for user1 (global policy)';
    ELSE
        RAISE EXCEPTION 'FAIL: is_mfa_required should return true for user1';
    END IF;

    -- is_mfa_required should return true for user2 too
    __required := unsecure.is_mfa_required(__user2_id, 1);
    IF __required THEN
        RAISE NOTICE 'PASS: is_mfa_required returns true for user2 (global policy)';
    ELSE
        RAISE EXCEPTION 'FAIL: is_mfa_required should return true for user2';
    END IF;

    -- Verify event logged
    IF EXISTS(
        SELECT 1 FROM auth.user_event ue
        WHERE ue.event_type_code = 'mfa_policy_created'
          AND (ue.event_data ->> 'mfa_policy_id')::bigint = __policy_id
    ) THEN
        RAISE NOTICE 'PASS: mfa_policy_created event logged';
    ELSE
        RAISE EXCEPTION 'FAIL: mfa_policy_created event not found';
    END IF;
END $$;
