/*
 * Example 03 — Tenants & owners
 * =============================
 *
 * Showcases multi-tenancy from the admin tenant (tenant 1):
 *   - creating a tenant with an initial owner
 *   - adding a second owner
 *   - cross-tenant reads (_tenant_id = 1 caller + _target_tenant_id = the tenant)
 *
 * Standalone plain SQL — run one statement at a time in any client. Data persists;
 * run examples/cleanup.sql to reset. Acts as the system user (user_id = 1).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;


-- ── Setup: two users to act as owners ────────────────────────────────────────
select * from auth.register_user('examples', 1, 'ex03',
        _email := 'benjamin.horne@twinpeaks.com', _password_hash := 'not-a-real-hash',
        _display_name := 'Benjamin Horne');
select * from auth.register_user('examples', 1, 'ex03',
        _email := 'catherine.martell@twinpeaks.com', _password_hash := 'not-a-real-hash',
        _display_name := 'Catherine Martell');


-- ── Aspect: create a tenant with an initial owner ────────────────────────────
-- _tenant_owner_id sets the first owner as part of creation.
select * from auth.create_tenant('examples', 1, 'ex03',
        _title := 'Great Northern Hotel', _code := 'great_northern',
        _tenant_owner_id := (select user_id from auth.user_info where email = 'benjamin.horne@twinpeaks.com'));


-- ── Aspect: add a second owner to the tenant ─────────────────────────────────
select * from auth.create_owner('examples', 1, 'ex03',
        _target_user_id := (select user_id from auth.user_info where email = 'catherine.martell@twinpeaks.com'),
        _tenant_id := (select tenant_id from auth.tenant where code = 'great_northern'));


-- ── Aspect: cross-tenant reads from the admin tenant ─────────────────────────
-- Caller is tenant 1 (admin); _target_tenant_id points at the new tenant.
select * from auth.get_tenant_users('examples', 1, 'ex03', 1,
        (select tenant_id from auth.tenant where code = 'great_northern'));

select * from auth.get_tenant_groups('examples', 1, 'ex03', 1,
        (select tenant_id from auth.tenant where code = 'great_northern'));

select * from auth.get_tenant_members('examples', 1, 'ex03', 1,
        (select tenant_id from auth.tenant where code = 'great_northern'));


-- ── Inspect owners on record ─────────────────────────────────────────────────
select o.tenant_id, u.display_name
from auth.owner o
join auth.user_info u on u.user_id = o.user_id
where o.tenant_id = (select tenant_id from auth.tenant where code = 'great_northern');
