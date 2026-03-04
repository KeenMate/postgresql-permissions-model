set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 8: get_mfa_policies — filter by tenant/group/user, unfiltered
-- ============================================================================
DO $$
DECLARE
    __user1_id      bigint  := current_setting('test.mfapol_user1_id')::bigint;
    __group_id      integer := current_setting('test.mfapol_group_id')::integer;
    __result        record;
    __count         integer;
    __global_id     bigint;
    __tenant_id_pol bigint;
    __group_id_pol  bigint;
    __user_id_pol   bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 8: get_mfa_policies filtering --';

    -- Re-create policies for filtering tests (previous test deleted all)
    SELECT __mfa_policy_id INTO __global_id
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-08a');

    SELECT __mfa_policy_id INTO __tenant_id_pol
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-08b', _tenant_id := 1);

    SELECT __mfa_policy_id INTO __group_id_pol
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-08c', _user_group_id := __group_id);

    SELECT __mfa_policy_id INTO __user_id_pol
    FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-08d', _target_user_id := __user1_id);

    -- Unfiltered: should return all 4
    SELECT count(*) INTO __count
    FROM auth.get_mfa_policies(1, 'test-corr-mfapol-08e');

    IF __count >= 4 THEN
        RAISE NOTICE 'PASS: Unfiltered get_mfa_policies returns >= 4 policies (got %)', __count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 4 policies unfiltered, got %', __count;
    END IF;

    -- Filter by tenant_id=1: should include tenant and possibly others with tenant_id=1
    SELECT count(*) INTO __count
    FROM auth.get_mfa_policies(1, 'test-corr-mfapol-08f', _tenant_id := 1);

    IF __count >= 1 THEN
        RAISE NOTICE 'PASS: Filter by tenant_id=1 returns >= 1 policy (got %)', __count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 1 policy with tenant_id=1, got %', __count;
    END IF;

    -- Filter by group: should return the group policy
    SELECT count(*) INTO __count
    FROM auth.get_mfa_policies(1, 'test-corr-mfapol-08g', _user_group_id := __group_id);

    IF __count >= 1 THEN
        RAISE NOTICE 'PASS: Filter by user_group_id returns >= 1 policy (got %)', __count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 1 policy with user_group_id, got %', __count;
    END IF;

    -- Filter by user: should return the user policy
    SELECT count(*) INTO __count
    FROM auth.get_mfa_policies(1, 'test-corr-mfapol-08h', _target_user_id := __user1_id);

    IF __count >= 1 THEN
        RAISE NOTICE 'PASS: Filter by target_user_id returns >= 1 policy (got %)', __count;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected >= 1 policy with target_user_id, got %', __count;
    END IF;

    -- Store for cleanup in later tests
    PERFORM set_config('test.mfapol_global_policy_id', __global_id::text, false);
    PERFORM set_config('test.mfapol_tenant_policy_id', __tenant_id_pol::text, false);
    PERFORM set_config('test.mfapol_group_policy_id', __group_id_pol::text, false);
    PERFORM set_config('test.mfapol_user_policy_id', __user_id_pol::text, false);
END $$;
