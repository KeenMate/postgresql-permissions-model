set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 11: delete_provider returns provider_id and journals event 16003
-- ============================================================================
DO $$
DECLARE
    __provider_id int;
    __returned_id int;
    __db_exists boolean;
    __journal_keys jsonb;
BEGIN
    RAISE NOTICE 'TEST 11: delete_provider returns provider_id and journals 16003';

    -- Use prov_test_ensure (no FK dependencies)
    SELECT provider_id INTO __provider_id FROM auth.provider WHERE code = 'prov_test_ensure';

    SELECT p.__provider_id
    FROM auth.delete_provider('prov_test', 1, 'prov-test-del', 'prov_test_ensure') p
    INTO __returned_id;

    IF __returned_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: delete_provider returned NULL provider_id';
    END IF;

    IF __returned_id != __provider_id THEN
        RAISE EXCEPTION '  FAIL: delete_provider returned % (expected %)', __returned_id, __provider_id;
    END IF;

    SELECT exists(SELECT 1 FROM auth.provider WHERE code = 'prov_test_ensure') INTO __db_exists;

    IF __db_exists THEN
        RAISE EXCEPTION '  FAIL: provider still exists after delete';
    END IF;

    SELECT j.keys
    FROM public.journal j
    WHERE j.event_id = 16003
      AND j.correlation_id = 'prov-test-del'
    ORDER BY j.created_at DESC
    LIMIT 1
    INTO __journal_keys;

    IF __journal_keys IS NOT NULL AND (__journal_keys->>'provider')::int = __provider_id THEN
        RAISE NOTICE '  PASS: deleted and journaled (id=%, journal_keys=%)', __returned_id, __journal_keys;
    ELSE
        RAISE EXCEPTION '  FAIL: journal entity_id is NULL or missing (keys=%)', __journal_keys;
    END IF;
END $$;

-- ============================================================================
-- TEST 12: delete_provider for non-existent code returns no rows
-- ============================================================================
DO $$
DECLARE
    __returned_id int;
BEGIN
    RAISE NOTICE 'TEST 12: delete_provider for non-existent code returns no rows';

    SELECT p.__provider_id
    FROM auth.delete_provider('prov_test', 1, 'prov-test-del2', 'prov_nonexistent_xyz') p
    INTO __returned_id;

    IF __returned_id IS NULL THEN
        RAISE NOTICE '  PASS: no rows returned for non-existent provider';
    ELSE
        RAISE EXCEPTION '  FAIL: expected NULL, got %', __returned_id;
    END IF;
END $$;
