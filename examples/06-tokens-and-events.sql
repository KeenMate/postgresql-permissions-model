/*
 * Example 06 — Audit events & single-use tokens
 * =============================================
 *
 * Showcases a password-reset flow:
 *   - record an audit event (every security action lands in auth.user_event)
 *   - issue a short-lived token tied to that event
 *   - validate + consume the token (single use)
 *   - observe that the token is now spent
 *
 * Standalone plain SQL — run one statement at a time in any client. Data persists;
 * run examples/cleanup.sql to reset. Acts as the system user (user_id = 1).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;


-- ── Setup: a user requesting a password reset ────────────────────────────────
select * from auth.register_user('examples', 1, 'ex06',
        _email := 'shelly.johnson@twinpeaks.com', _password_hash := 'old-hash',
        _display_name := 'Shelly Johnson');


-- ── Aspect: record an audit event ────────────────────────────────────────────
-- _request_context carries ambient request info (ip, user agent, …) for auditing.
select * from auth.create_user_event('examples', 1, 'ex06',
        _event_type_code := 'password_reset_requested',
        _target_user_id  := (select user_id from auth.user_info where email = 'shelly.johnson@twinpeaks.com'),
        _request_context := '{"ip": "203.0.113.5", "user_agent": "ExampleAgent/1.0", "domain": "twinpeaks.com"}');


-- ── Aspect: issue a short-lived token linked to that event ───────────────────
select * from auth.create_token('examples', 1, 'ex06',
        _target_user_id     := (select user_id from auth.user_info where email = 'shelly.johnson@twinpeaks.com'),
        _target_user_oid    := null,
        _user_event_id      := (select user_event_id::int from auth.user_event
                                where target_user_id = (select user_id from auth.user_info where email = 'shelly.johnson@twinpeaks.com')
                                order by user_event_id desc limit 1),
        _token_type_code    := 'password_reset',
        _token_channel_code := 'email',
        _token              := 'DEMO-RESET-TOKEN');


-- ── Aspect: validate + consume the token (single use) ────────────────────────
-- _set_as_used := true marks it consumed so it cannot be replayed.
select * from auth.validate_token('examples', 1, 'ex06',
        _target_user_id  := (select user_id from auth.user_info where email = 'shelly.johnson@twinpeaks.com'),
        _token_uid       := (select uid from auth.token
                             where token = 'DEMO-RESET-TOKEN' and token_type_code = 'password_reset'
                             order by token_id desc limit 1),
        _token           := 'DEMO-RESET-TOKEN',
        _token_type_code := 'password_reset',
        _request_context := '{"ip": "203.0.113.5", "user_agent": "ExampleAgent/1.0"}',
        _set_as_used     := true);


-- ── Aspect: the token is now spent ───────────────────────────────────────────
-- Re-validating a used token *raises* (error 52278) by design — the intended
-- login-flow behaviour — so we inspect the stored state instead of calling again.
select uid, token_state_code, used_at
from auth.token where token = 'DEMO-RESET-TOKEN';   -- token_state_code = 'used'


-- ── Inspect the audit trail ──────────────────────────────────────────────────
select user_event_id, event_type_code, created_at
from auth.user_event
where target_user_id = (select user_id from auth.user_info where email = 'shelly.johnson@twinpeaks.com')
order by user_event_id;
