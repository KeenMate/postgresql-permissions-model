set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 11: get_invitations — list with filters
-- ============================================================================
DO $$
DECLARE
    __inviter_id bigint;
    __count bigint;
BEGIN
    RAISE NOTICE 'TEST 11: get_invitations — listing and filtering';

    SELECT val FROM _inv_test_data WHERE key = 'inviter_id' INTO __inviter_id;

    -- Get all invitations for tenant 1 (should have several from previous tests)
    SELECT count(*) FROM auth.get_invitations('svc_app', __inviter_id, 'inv-corr-list', 1) INTO __count;
    IF __count >= 3 THEN
        RAISE NOTICE '  PASS: Found % invitations for tenant 1', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 3 invitations, got %', __count;
    END IF;

    -- Filter by status
    SELECT count(*) FROM auth.get_invitations('svc_app', __inviter_id, 'inv-corr-list', 1, _status_code := 'completed') INTO __count;
    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Found % completed invitations', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 1 completed invitation, got %', __count;
    END IF;

    -- Filter by target email substring
    SELECT count(*) FROM auth.get_invitations('svc_app', __inviter_id, 'inv-corr-list', 1, _target_email := '+420') INTO __count;
    IF __count >= 1 THEN
        RAISE NOTICE '  PASS: Found % invitations matching "+420"', __count;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected at least 1 invitation matching +420, got %', __count;
    END IF;

    RAISE NOTICE 'TEST 11: Done';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 12: get_invitation_actions — verify action details
-- ============================================================================
DO $$
DECLARE
    __inviter_id bigint;
    __inv_id bigint;
    __count bigint;
    __action record;
BEGIN
    RAISE NOTICE 'TEST 12: get_invitation_actions';

    SELECT val FROM _inv_test_data WHERE key = 'inviter_id' INTO __inviter_id;
    SELECT val FROM _inv_test_data WHERE key = 'inv_id_1' INTO __inv_id;

    -- Get actions for first invitation (from test 1)
    SELECT count(*) FROM auth.get_invitation_actions('svc_app', __inviter_id, 'inv-corr-acts', __inv_id) INTO __count;
    IF __count = 2 THEN
        RAISE NOTICE '  PASS: Found 2 actions for invitation %', __inv_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected 2 actions, got %', __count;
    END IF;

    -- Verify actions have phase and condition codes
    SELECT __phase_code, __condition_code, __action_type_code
    FROM auth.get_invitation_actions('svc_app', __inviter_id, 'inv-corr-acts', __inv_id)
    LIMIT 1
    INTO __action;

    IF __action.__phase_code IS NOT NULL AND __action.__condition_code IS NOT NULL THEN
        RAISE NOTICE '  PASS: Actions have phase_code=% and condition_code=%', __action.__phase_code, __action.__condition_code;
    ELSE
        RAISE EXCEPTION '  FAIL: Actions missing phase or condition code';
    END IF;

    RAISE NOTICE 'TEST 12: Done';
    RAISE NOTICE '';
END $$;
