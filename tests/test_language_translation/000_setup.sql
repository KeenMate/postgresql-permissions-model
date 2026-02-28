set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- SETUP: Ensure system admin user exists for permission checks
-- ============================================================================
DO $$
DECLARE
    __test_user_id bigint;
BEGIN
    RAISE NOTICE 'SETUP: Preparing test environment...';

    -- Use system user (user_id=1) which has system_admin perm set
    SELECT user_id INTO __test_user_id FROM auth.user_info WHERE user_id = 1;

    IF __test_user_id IS NULL THEN
        RAISE EXCEPTION 'SETUP FAILED: System user (id=1) not found. Run seed data first.';
    END IF;

    RAISE NOTICE 'SETUP: Using system user_id=% for permission checks', __test_user_id;
    RAISE NOTICE '';
END $$;
