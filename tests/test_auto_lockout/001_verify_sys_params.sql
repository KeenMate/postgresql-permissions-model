set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 1: Auto-lockout sys_param values are readable
-- ============================================================================
DO $$
DECLARE
    __max_attempts bigint;
    __window_min   bigint;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 1: Verify sys_param values --';

    SELECT sp.number_value
    FROM const.sys_param sp
    WHERE sp.group_code = 'login_lockout' AND sp.code = 'max_failed_attempts'
    INTO __max_attempts;

    SELECT sp.number_value
    FROM const.sys_param sp
    WHERE sp.group_code = 'login_lockout' AND sp.code = 'window_minutes'
    INTO __window_min;

    IF __max_attempts = 5 AND __window_min = 15 THEN
        RAISE NOTICE 'PASS: login_lockout sys_params correct (max_attempts=%, window_minutes=%)', __max_attempts, __window_min;
    ELSE
        RAISE EXCEPTION 'FAIL: Expected max_attempts=5, window_minutes=15 but got %, %', __max_attempts, __window_min;
    END IF;
END $$;
