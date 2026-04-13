set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- TEST 6: auth.update_user_password changes password_hash on user_identity
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-pwd-' || gen_random_uuid()::text;
    __new_hash text := 'updated_hash_' || gen_random_uuid()::text;
    __found_hash text;
    __result_user_id bigint;
BEGIN
    RAISE NOTICE 'TEST 6: auth.update_user_password changes password_hash on user_identity';

    -- Update password (system user updating test user, has permission)
    SELECT __user_id INTO __result_user_id
    FROM auth.update_user_password(
        'audit_test',
        __system_user_id,
        __corr_id,
        __test_user_id,
        __new_hash,
        '{"ip": "127.0.0.1"}'::jsonb
    );

    IF __result_user_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: update_user_password returned null (no email identity found?)';
    END IF;

    -- Verify the hash changed on user_identity
    SELECT ui.password_hash INTO __found_hash
    FROM auth.user_identity ui
    WHERE ui.user_id = __test_user_id
      AND ui.provider_code = 'email';

    IF __found_hash = __new_hash THEN
        RAISE NOTICE '  PASS: password_hash updated successfully';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected hash=%, found=%', __new_hash, __found_hash;
    END IF;
END $$;

-- ============================================================================
-- TEST 7: auth.update_user_password for self (same user_id = target_user_id)
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-selfpwd-' || gen_random_uuid()::text;
    __self_hash text := 'self_hash_' || gen_random_uuid()::text;
    __found_hash text;
BEGIN
    RAISE NOTICE 'TEST 7: auth.update_user_password for self (no permission check)';

    -- Self-update skips permission check
    PERFORM auth.update_user_password(
        'audit_test',
        __test_user_id,
        __corr_id,
        __test_user_id,
        __self_hash,
        null::jsonb
    );

    SELECT ui.password_hash INTO __found_hash
    FROM auth.user_identity ui
    WHERE ui.user_id = __test_user_id
      AND ui.provider_code = 'email';

    IF __found_hash = __self_hash THEN
        RAISE NOTICE '  PASS: Self password update succeeded without permission check';
    ELSE
        RAISE EXCEPTION '  FAIL: Expected hash=%, found=%', __self_hash, __found_hash;
    END IF;
END $$;

-- ============================================================================
-- TEST 8: auth.update_user_preferences merges jsonb preferences
-- ============================================================================
DO $$
DECLARE
    __system_user_id bigint := 1;
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-prefs-' || gen_random_uuid()::text;
    __prefs text;
BEGIN
    RAISE NOTICE 'TEST 8: auth.update_user_preferences merges jsonb preferences';

    -- Set initial preferences
    PERFORM auth.update_user_preferences(
        'audit_test',
        __test_user_id,
        __corr_id,
        __test_user_id,
        '{"theme": "dark", "lang": "en"}'
    );

    -- Merge additional preference
    PERFORM auth.update_user_preferences(
        'audit_test',
        __test_user_id,
        __corr_id,
        __test_user_id,
        '{"lang": "cs", "notifications": true}'
    );

    -- Verify merge: theme should remain, lang should be overwritten, notifications added
    SELECT ui.user_preferences::text INTO __prefs
    FROM auth.user_info ui
    WHERE ui.user_id = __test_user_id;

    IF __prefs::jsonb ->> 'theme' = 'dark'
       AND __prefs::jsonb ->> 'lang' = 'cs'
       AND (__prefs::jsonb ->> 'notifications')::boolean = true THEN
        RAISE NOTICE '  PASS: Preferences merged correctly: %', __prefs;
    ELSE
        RAISE EXCEPTION '  FAIL: Preferences not merged as expected: %', __prefs;
    END IF;
END $$;

-- ============================================================================
-- TEST 9: auth.get_user_preferences returns stored preferences
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __corr_id text := 'audit-test-getprefs-' || gen_random_uuid()::text;
    __result text;
BEGIN
    RAISE NOTICE 'TEST 9: auth.get_user_preferences returns stored preferences';

    -- Preferences were set in TEST 8; retrieve them
    SELECT __value INTO __result
    FROM auth.get_user_preferences(
        __test_user_id,
        __corr_id,
        __test_user_id
    );

    IF __result IS NOT NULL AND __result::jsonb ->> 'theme' = 'dark' THEN
        RAISE NOTICE '  PASS: get_user_preferences returned: %', __result;
    ELSE
        RAISE EXCEPTION '  FAIL: get_user_preferences returned unexpected value: %', __result;
    END IF;
END $$;

-- ============================================================================
-- TEST 10: auth.update_user_last_selected_tenant sets tenant on user_info
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint := current_setting('test.audit_user_id')::bigint;
    __tenant_uuid text := current_setting('test.audit_tenant_uuid');
    __corr_id text := 'audit-test-tenant-' || gen_random_uuid()::text;
    __result_tenant_id integer;
    __found_tenant_id integer;
BEGIN
    RAISE NOTICE 'TEST 10: auth.update_user_last_selected_tenant sets tenant on user_info';

    -- Self-service: test user updates their own last selected tenant (no permission check)
    SELECT __tenant_id INTO __result_tenant_id
    FROM auth.update_user_last_selected_tenant(
        'audit_test',
        __test_user_id,
        __corr_id,
        __test_user_id,
        __tenant_uuid
    );

    IF __result_tenant_id IS NULL THEN
        RAISE EXCEPTION '  FAIL: update_user_last_selected_tenant returned null tenant_id (user may not be in a tenant 1 group)';
    END IF;

    -- Verify on user_info
    SELECT ui.last_selected_tenant_id INTO __found_tenant_id
    FROM auth.user_info ui
    WHERE ui.user_id = __test_user_id;

    IF __found_tenant_id = __result_tenant_id THEN
        RAISE NOTICE '  PASS: last_selected_tenant_id=% set on user_info', __found_tenant_id;
    ELSE
        RAISE EXCEPTION '  FAIL: Expected tenant_id=%, found=%', __result_tenant_id, __found_tenant_id;
    END IF;
END $$;
