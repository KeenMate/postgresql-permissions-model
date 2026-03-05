set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Verify all expected permission trees exist (top-level parent codes)
-- ============================================================================
DO $$
DECLARE
    __missing text;
BEGIN
    RAISE NOTICE '-- Permission Trees --';

    -- All top-level permission parents that should exist after setup
    SELECT string_agg(p, ', ')
    FROM unnest(ARRAY[
        'users', 'groups', 'permissions', 'tenants', 'providers',
        'api_keys', 'tokens', 'authentication', 'journal',
        'languages', 'translations', 'resources',
        'mfa'
    ]) AS p
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.permission perm WHERE perm.code = p AND perm.full_code::text = p
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing top-level permission trees: %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All top-level permission trees exist';

    -- MFA sub-permissions (created by 036_tables_mfa.sql)
    SELECT string_agg(p, ', ')
    FROM unnest(ARRAY[
        'mfa.enroll_mfa', 'mfa.confirm_mfa_enrollment', 'mfa.disable_mfa',
        'mfa.get_mfa_status', 'mfa.create_mfa_challenge', 'mfa.verify_mfa_challenge'
    ]) AS p
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.permission perm WHERE perm.full_code::text = p
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing MFA permissions (from 036): %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All MFA core permissions exist';

    -- MFA Policy sub-permissions (created by 039_mfa_policy.sql)
    SELECT string_agg(p, ', ')
    FROM unnest(ARRAY[
        'mfa.reset_mfa', 'mfa.mfa_policy',
        'mfa.mfa_policy.create_mfa_policy', 'mfa.mfa_policy.delete_mfa_policy',
        'mfa.mfa_policy.get_mfa_policies'
    ]) AS p
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.permission perm WHERE perm.full_code::text = p
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing MFA Policy permissions (from 039): %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All MFA Policy permissions exist';

    -- Auto-lockout event codes (from 036_tables_mfa.sql)
    SELECT string_agg(c, ', ')
    FROM unnest(ARRAY[
        'user_auto_locked',
        'mfa_enrolled', 'mfa_enrollment_confirmed', 'mfa_disabled',
        'mfa_challenge_created', 'mfa_challenge_passed', 'mfa_challenge_failed', 'mfa_recovery_used',
        'mfa_policy_created', 'mfa_policy_deleted', 'mfa_recovery_reset'
    ]) AS c
    WHERE NOT EXISTS (
        SELECT 1 FROM const.event_code ec WHERE ec.code = c
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing event codes: %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All MFA and auto-lockout event codes exist';

    -- Auto-lockout sys_param entries
    SELECT string_agg(c, ', ')
    FROM unnest(ARRAY['max_failed_attempts', 'window_minutes']) AS c
    WHERE NOT EXISTS (
        SELECT 1 FROM const.sys_param sp WHERE sp.group_code = 'login_lockout' AND sp.code = c
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing login_lockout sys_params: %', __missing;
    END IF;
    RAISE NOTICE 'PASS: Auto-lockout sys_param entries exist';
END $$;
