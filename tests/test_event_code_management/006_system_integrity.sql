set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 20: System events still intact after all tests
-- ============================================================================
DO $$
DECLARE
    __system_count int;
    __system_msg_count int;
BEGIN
    RAISE NOTICE 'TEST 20: System events remain intact';

    SELECT count(*) INTO __system_count FROM const.event_code WHERE is_system = true;
    SELECT count(*) INTO __system_msg_count
    FROM const.event_message em
    JOIN const.event_code ec ON ec.event_id = em.event_id
    WHERE ec.is_system = true;

    IF __system_count > 0 AND __system_msg_count > 0 THEN
        RAISE NOTICE '  PASS: % system event codes and % system messages intact',
            __system_count, __system_msg_count;
    ELSE
        RAISE EXCEPTION '  FAIL: System data missing (codes=%, messages=%)',
            __system_count, __system_msg_count;
    END IF;
END $$;
