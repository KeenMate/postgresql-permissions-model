set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 1: disable_user_identity sets is_active=false
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-disable-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 1: disable_user_identity sets is_active=false';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT * INTO __result
    FROM auth.disable_user_identity('idp_test', 1, __corr_id, __target_user_id, 'test_idp');

    IF __result.__user_identity_id IS NOT NULL AND __result.__is_active = false THEN
        RAISE NOTICE '  PASS: identity disabled (id=%, is_active=%)', __result.__user_identity_id, __result.__is_active;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_active=false, got id=%, is_active=%', __result.__user_identity_id, __result.__is_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: verify disabled identity in table
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __is_active boolean;
BEGIN
    RAISE NOTICE 'TEST 2: verify disabled identity in user_identity table';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT uid.is_active INTO __is_active
    FROM auth.user_identity uid
    WHERE uid.user_id = __target_user_id AND uid.provider_code = 'test_idp';

    IF __is_active = false THEN
        RAISE NOTICE '  PASS: identity is_active=false in table';
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_active=false, got %', __is_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: enable_user_identity sets is_active=true
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-enable-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 3: enable_user_identity sets is_active=true';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT * INTO __result
    FROM auth.enable_user_identity('idp_test', 1, __corr_id, __target_user_id, 'test_idp');

    IF __result.__user_identity_id IS NOT NULL AND __result.__is_active = true THEN
        RAISE NOTICE '  PASS: identity enabled (id=%, is_active=%)', __result.__user_identity_id, __result.__is_active;
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_active=true, got id=%, is_active=%', __result.__user_identity_id, __result.__is_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 4: verify enabled identity in table
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __is_active boolean;
BEGIN
    RAISE NOTICE 'TEST 4: verify enabled identity in user_identity table';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT uid.is_active INTO __is_active
    FROM auth.user_identity uid
    WHERE uid.user_id = __target_user_id AND uid.provider_code = 'test_idp';

    IF __is_active = true THEN
        RAISE NOTICE '  PASS: identity is_active=true in table';
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_active=true, got %', __is_active;
    END IF;
END $$;

-- ============================================================================
-- TEST 5: verify_user_identity marks identity as verified
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __is_verified boolean;
    __corr_id text := 'idp-verify-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 5: verify_user_identity marks identity as verified';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    -- ensure_user_from_provider already sets is_verified=true, so reset it first
    UPDATE auth.user_identity
    SET is_verified = false
    WHERE user_id = __target_user_id AND provider_code = 'test_idp';

    -- verify it is false
    SELECT uid.is_verified INTO __is_verified
    FROM auth.user_identity uid
    WHERE uid.user_id = __target_user_id AND uid.provider_code = 'test_idp';

    IF __is_verified <> false THEN
        RAISE EXCEPTION '  FAIL: expected is_verified=false after reset, got %', __is_verified;
    END IF;

    -- now call verify
    PERFORM auth.verify_user_identity('idp_test', 1, __corr_id, __target_user_id, 'test_idp');

    SELECT uid.is_verified INTO __is_verified
    FROM auth.user_identity uid
    WHERE uid.user_id = __target_user_id AND uid.provider_code = 'test_idp';

    IF __is_verified = true THEN
        RAISE NOTICE '  PASS: identity is_verified=true after verify_user_identity';
    ELSE
        RAISE EXCEPTION '  FAIL: expected is_verified=true, got %', __is_verified;
    END IF;
END $$;

-- ============================================================================
-- TEST 6: get_user_identity returns correct identity data
-- ============================================================================
DO $$
DECLARE
    __target_user_id bigint;
    __result record;
    __corr_id text := 'idp-get-id-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 6: get_user_identity returns correct identity data';

    __target_user_id := current_setting('test.idp_user_id')::bigint;

    SELECT * INTO __result
    FROM auth.get_user_identity(1, __corr_id, __target_user_id, 'test_idp');

    IF __result.__user_identity_id IS NOT NULL
       AND __result.__provider_code = 'test_idp'
       AND __result.__uid = 'idp_test_uid_1'
       AND __result.__user_id = __target_user_id
       AND __result.__is_verified = true THEN
        RAISE NOTICE '  PASS: identity returned (id=%, provider=%, uid=%, verified=%)',
            __result.__user_identity_id, __result.__provider_code, __result.__uid, __result.__is_verified;
    ELSE
        RAISE EXCEPTION '  FAIL: unexpected identity data (id=%, provider=%, uid=%, user_id=%, verified=%)',
            __result.__user_identity_id, __result.__provider_code, __result.__uid, __result.__user_id, __result.__is_verified;
    END IF;
END $$;
