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

-- Required by auth.user_info table default for 'code' column
create or replace function auth.get_user_random_code() returns text
    parallel safe
    cost 1
    language sql
as
$$
select helpers.random_string(8);
$$;
