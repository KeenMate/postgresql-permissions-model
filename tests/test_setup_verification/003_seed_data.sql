set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Verify seed data was loaded: service accounts, tenant, providers, event codes
-- ============================================================================
DO $$
DECLARE
    __count bigint;
    __missing text;
BEGIN
    RAISE NOTICE '-- Seed Data --';

    -- Service accounts (user_ids 1-6, 800)
    SELECT string_agg(u::text, ', ')
    FROM unnest(ARRAY[1, 2, 3, 4, 5, 6, 800]) AS u
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.user_info ui WHERE ui.user_id = u
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing service accounts (user_ids): %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All service accounts exist (user_ids 1-6, 800)';

    -- Primary tenant
    SELECT count(*) FROM auth.tenant WHERE tenant_id = 1 INTO __count;
    IF __count = 0 THEN
        RAISE EXCEPTION 'FAIL: Primary tenant (id=1) does not exist';
    END IF;
    RAISE NOTICE 'PASS: Primary tenant exists';

    -- Email provider
    SELECT count(*) FROM auth.provider WHERE code = 'email' INTO __count;
    IF __count = 0 THEN
        RAISE EXCEPTION 'FAIL: Email provider does not exist';
    END IF;
    RAISE NOTICE 'PASS: Email provider exists';

    -- Event codes should be populated
    SELECT count(*) FROM const.event_code INTO __count;
    IF __count < 50 THEN
        RAISE EXCEPTION 'FAIL: Expected at least 50 event codes, found %', __count;
    END IF;
    RAISE NOTICE 'PASS: Event codes populated (% codes)', __count;

    -- Permissions should be populated
    SELECT count(*) FROM auth.permission INTO __count;
    IF __count < 100 THEN
        RAISE EXCEPTION 'FAIL: Expected at least 100 permissions, found %', __count;
    END IF;
    RAISE NOTICE 'PASS: Permissions populated (% permissions)', __count;
END $$;
