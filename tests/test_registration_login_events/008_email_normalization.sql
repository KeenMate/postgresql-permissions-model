set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 17: register_user normalizes email and preserves original_email
--   email          -> lower(trim(...))   (canonical, used for lookups)
--   original_email -> trim(...)          (case preserved, as supplied)
--   user_identity.uid -> lower(trim(...))
-- ============================================================================
DO $$
DECLARE
    __result       record;
    __email        text;
    __orig_email   text;
    __uid          text;
    __corr_id      text := 'reg-email-norm-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 17: register_user normalizes email, keeps original_email';

    -- Supplied with mixed case AND surrounding whitespace
    SELECT * INTO __result
    FROM auth.register_user('reg_test', 1, __corr_id, '  RegTest.Norm@Test.COM  ', '$hash$norm', 'RegTest Norm');

    SELECT ui.email, ui.original_email
    INTO __email, __orig_email
    FROM auth.user_info ui
    WHERE ui.user_id = __result.__user_id;

    SELECT uid.uid
    INTO __uid
    FROM auth.user_identity uid
    WHERE uid.user_id = __result.__user_id AND uid.provider_code = 'email';

    IF __email = 'regtest.norm@test.com'
       AND __orig_email = 'RegTest.Norm@Test.COM'
       AND __uid = 'regtest.norm@test.com' THEN
        RAISE NOTICE '  PASS: email=%, original_email=%, uid=%', __email, __orig_email, __uid;
    ELSE
        RAISE EXCEPTION '  FAIL: email=%, original_email=%, uid=%', __email, __orig_email, __uid;
    END IF;
END $$;

-- ============================================================================
-- TEST 18: ensure_user_from_provider update path re-normalizes email
--   Regression guard for the fixed unsecure.update_user_info_basic_data:
--   a returning provider user whose email genuinely changes must store the
--   new email NORMALIZED in the email column and the raw value in original_email.
--   (Previously the update path wrote the raw email into the email column.)
-- ============================================================================
DO $$
DECLARE
    __result     record;
    __user_id    bigint;
    __email      text;
    __orig_email text;
    __corr_id    text := 'prov-email-norm-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 18: ensure_user_from_provider update path normalizes changed email';

    -- First login: create the provider user with an initial email
    SELECT * INTO __result
    FROM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad',
        'regtest_norm_uid', 'regtest_norm_oid', 'regtest_norm_user', 'RegTest Norm User',
        'first.email@test.com');
    __user_id := __result.__user_id;

    -- Re-login with a genuinely different email (different normalized value),
    -- supplied mixed-case -> forces the update path to run.
    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad',
        'regtest_norm_uid', 'regtest_norm_oid', 'regtest_norm_user', 'RegTest Norm User',
        'Second.Email@Test.COM');

    SELECT ui.email, ui.original_email
    INTO __email, __orig_email
    FROM auth.user_info ui
    WHERE ui.user_id = __user_id;

    IF __email = 'second.email@test.com' AND __orig_email = 'Second.Email@Test.COM' THEN
        RAISE NOTICE '  PASS: email=%, original_email=%', __email, __orig_email;
    ELSE
        RAISE EXCEPTION '  FAIL: email=%, original_email=% (email column must be normalized)', __email, __orig_email;
    END IF;

    PERFORM set_config('test.norm_user_id', __user_id::text, false);
END $$;

-- ============================================================================
-- TEST 19: update path never lets a raw (mixed-case) email leak into email column
--   Force the update to fire via a display_name change while passing a
--   mixed-case email. The email column must stay lower(trim(...)); original_email
--   captures the raw casing. This is the exact path that was previously buggy.
-- ============================================================================
DO $$
DECLARE
    __user_id    bigint;
    __email      text;
    __orig_email text;
    __corr_id    text := 'prov-email-leak-' || gen_random_uuid()::text;
BEGIN
    RAISE NOTICE 'TEST 19: update path keeps email column normalized (no raw leak)';

    __user_id := current_setting('test.norm_user_id')::bigint;

    -- display_name differs -> update fires; email passed mixed-case
    PERFORM auth.ensure_user_from_provider('reg_test', 1, __corr_id, 'aad',
        'regtest_norm_uid', 'regtest_norm_oid', 'regtest_norm_user', 'RegTest Norm Renamed',
        'Second.Email@Test.COM');

    SELECT ui.email, ui.original_email
    INTO __email, __orig_email
    FROM auth.user_info ui
    WHERE ui.user_id = __user_id;

    IF __email = 'second.email@test.com' AND __orig_email = 'Second.Email@Test.COM' THEN
        RAISE NOTICE '  PASS: email stays normalized=%, original_email=%', __email, __orig_email;
    ELSE
        RAISE EXCEPTION '  FAIL: email=%, original_email=% (raw email must not leak into email column)', __email, __orig_email;
    END IF;
END $$;
