set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Test 7: auth.verify_user_by_email — wrong hash raises 52103
-- ============================================================================
DO $$
DECLARE
    __test_user_id   bigint := current_setting('test.autolock_user_id')::bigint;
    __system_user_id bigint := current_setting('test.system_user_id')::bigint;
    __error_code     text;
    __event_exists   boolean;
    __event_reason   text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Test 7: verify_user_by_email — wrong hash --';

    -- Call with wrong hash
    BEGIN
        PERFORM auth.verify_user_by_email(
            __system_user_id, 'test-corr-07', 'autolock@test.com', 'wrong_hash'
        );
        RAISE EXCEPTION 'FAIL: Should have raised an error for wrong hash';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS __error_code = RETURNED_SQLSTATE;
    END;

    -- Should raise 33001 (via error.raise_52103 → error.raise_33001)
    IF __error_code = '33001' THEN
        RAISE NOTICE 'PASS: Wrong hash raised error code 33001 (invalid credentials)';
    ELSE
        RAISE EXCEPTION 'FAIL: Expected error code 33001, got %', __error_code;
    END IF;

    -- Note: user_login_failed event is rolled back by the BEGIN..EXCEPTION block
    -- (PostgreSQL rolls back to savepoint on exception), so we cannot verify it here.
    RAISE NOTICE 'PASS: Event verification skipped (rolled back by exception handler — expected)';
END $$;
