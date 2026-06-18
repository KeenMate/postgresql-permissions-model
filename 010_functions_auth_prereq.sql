/*
 * Auth Prerequisite Functions
 * ===========================
 *
 * Functions needed before auth tables can be created (used in table defaults)
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Extracted from WHOLE_DB.sql
 */

-- Set search_path for all subsequent operations (persists for session)
set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Start of the v2 line for the postgresql_permissionmodel component.
-- v2 spans files 010 → 047 (last seed). The matching stop_version_update
-- lives at the end of 047_seed_permissions.sql. Date-tagged work within v2
-- is tracked in CHANGELOG.md, not as separate component versions.
select * from public.start_version_update('2',
    'Major restructure: removed inheritance, new event codes',
    _component := 'postgresql_permissionmodel');

-- Required by auth.user_info table default for 'code' column
create or replace function auth.get_user_random_code() returns text
    parallel safe
    cost 1
    language sql
as
$$
select helpers.random_string(8);
$$;
