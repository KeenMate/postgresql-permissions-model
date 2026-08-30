/*
 * Example 02 — User status vs. identity status
 * ============================================
 *
 * Showcases the two independent axes of "can this user log in":
 *   - account level : enabled/disabled, locked/unlocked (the whole user)
 *   - identity level: enabled/disabled per provider (one login method)
 *
 * A disabled OR locked account is blocked regardless of identities; disabling a
 * single identity only blocks that one provider.
 *
 * Standalone plain SQL — run one statement at a time in any client. Data persists;
 * run examples/cleanup.sql to reset. Acts as the system user (user_id = 1).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;


-- ── Setup: a target user (local registration also creates an 'email' identity) ─
select * from auth.register_user('examples', 1, 'ex02',
        _email := 'bobby.briggs@twinpeaks.com', _password_hash := 'not-a-real-hash',
        _display_name := 'Bobby Briggs');


-- ── Aspect: disable / enable the whole account ───────────────────────────────
select * from auth.disable_user('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'));
select * from auth.enable_user('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'));


-- ── Aspect: lock / unlock the account (e.g. security hold, failed logins) ────
select * from auth.lock_user('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'));
select * from auth.unlock_user('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'));


-- ── Aspect: disable / enable a single provider identity ──────────────────────
-- Blocks only the 'email' login for this user; other identities keep working.
select * from auth.disable_user_identity('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'), 'email');
select * from auth.enable_user_identity('examples', 1, 'ex02',
        (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com'), 'email');


-- ── Inspect the resulting state ──────────────────────────────────────────────
select user_id, username, is_active, is_locked
from auth.user_info
where email = 'bobby.briggs@twinpeaks.com';

select provider_code, is_active
from auth.user_identity
where user_id = (select user_id from auth.user_info where email = 'bobby.briggs@twinpeaks.com');
