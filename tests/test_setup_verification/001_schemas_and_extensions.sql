set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- Verify all required schemas and extensions exist after setup
-- ============================================================================
DO $$
DECLARE
    __missing text;
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Test: Setup Verification';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '';
    RAISE NOTICE '-- Schemas & Extensions --';

    -- Check required schemas
    SELECT string_agg(s, ', ')
    FROM unnest(ARRAY['public', 'auth', 'const', 'ext', 'helpers', 'internal', 'unsecure', 'error', 'stage', 'triggers']) AS s
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.schemata sch WHERE sch.schema_name = s
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing schemas: %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All required schemas exist';

    -- Check required extensions
    SELECT string_agg(e, ', ')
    FROM unnest(ARRAY['uuid-ossp', 'ltree', 'unaccent', 'pgcrypto', 'pg_trgm']) AS e
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = e
    )
    INTO __missing;

    IF __missing IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Missing extensions: %', __missing;
    END IF;
    RAISE NOTICE 'PASS: All required extensions exist';
END $$;
