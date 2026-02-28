set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: user_registered event code exists in seed data
-- ============================================================================
DO $$
DECLARE
    __event_id integer;
    __code text;
BEGIN
    RAISE NOTICE 'TEST 1: user_registered event code (10008) exists';

    SELECT event_id, code INTO __event_id, __code
    FROM const.event_code
    WHERE event_id = 10008;

    IF __event_id = 10008 AND __code = 'user_registered' THEN
        RAISE NOTICE '  PASS: Event code 10008 "user_registered" exists';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected event_id=10008, code=user_registered, got event_id=%, code=%', __event_id, __code;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: user_registered message template exists
-- ============================================================================
DO $$
DECLARE
    __template text;
BEGIN
    RAISE NOTICE 'TEST 2: user_registered message template exists';

    SELECT message_template INTO __template
    FROM const.event_message
    WHERE event_id = 10008 AND language_code = 'en';

    IF __template IS NOT NULL AND __template LIKE '%registered%' THEN
        RAISE NOTICE '  PASS: Message template found: "%"', __template;
    ELSE
        RAISE EXCEPTION '  FAIL: Message template for 10008/en not found or unexpected: %', __template;
    END IF;
END $$;
