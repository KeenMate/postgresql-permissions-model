set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 9: Policy errors — delete non-existent (38007), duplicate scope
-- ============================================================================
DO $$
DECLARE
    __err_code text;
    __result   record;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 9: MFA policy error cases --';

    -- Case 1: Delete non-existent policy → 38007
    BEGIN
        PERFORM auth.delete_mfa_policy('test', 1, 'test-corr-mfapol-09a', 999999);
        RAISE EXCEPTION 'FAIL: delete_mfa_policy should have raised 38007 for non-existent policy';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __err_code = RETURNED_SQLSTATE;
        IF __err_code = '38007' THEN
            RAISE NOTICE 'PASS: delete_mfa_policy raised 38007 for non-existent policy';
        ELSE
            RAISE EXCEPTION 'FAIL: Expected 38007, got %', __err_code;
        END IF;
    END;

    -- Case 2: Duplicate scope → unique violation (23505)
    -- Global policy already exists from test 8
    BEGIN
        SELECT * INTO __result
        FROM auth.create_mfa_policy('test', 1, 'test-corr-mfapol-09b');
        RAISE EXCEPTION 'FAIL: Duplicate global policy should raise unique violation';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'PASS: Duplicate global policy raises unique_violation';
    END;
END $$;
