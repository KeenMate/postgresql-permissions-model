set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 3: update_provider modifies fields and journals event 16002
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __returned_id int;
    __db_name text;
    __journal_keys jsonb;
BEGIN
    RAISE NOTICE 'TEST 3: update_provider modifies fields and journals 16002';

    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_1';

    SELECT p.__provider_id
    FROM auth.update_provider('prov_test', 1, 'prov-test-upd', __provider_id, 'prov_test_1', 'Provider Test 1 Updated', true) p
    INTO __returned_id;

    IF __returned_id IS NULL OR __returned_id != __provider_id THEN
        RAISE EXCEPTION '  FAIL: update_provider returned % (expected %)', __returned_id, __provider_id;
    END IF;

    SELECT name INTO __db_name FROM auth.provider WHERE provider_id = __provider_id;

    IF __db_name != 'Provider Test 1 Updated' THEN
        RAISE EXCEPTION '  FAIL: name not updated (got "%")', __db_name;
    END IF;

    SELECT j.keys
    FROM public.journal j
    WHERE j.event_id = 16002
      AND j.correlation_id = 'prov-test-upd'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys;

    IF __journal_keys IS NOT NULL AND (__journal_keys->>'provider')::int = __provider_id THEN
        RAISE NOTICE '  PASS: updated and journaled (id=%, name="%")', __returned_id, __db_name;
    ELSE
        RAISE EXCEPTION '  FAIL: journal mismatch for 16002 (keys=%)', __journal_keys;
    END IF;
END $$;
