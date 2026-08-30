/*
 * Example 04 — Groups & external mappings
 * =======================================
 *
 * Showcases the three group membership models:
 *   - internal : members added explicitly
 *   - external : membership derived only from external provider group/role maps
 *   - hybrid   : both explicit members AND external mappings
 *
 * Standalone plain SQL — run one statement at a time in any client. Data persists;
 * run examples/cleanup.sql to reset. Acts as the system user (user_id = 1).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;


-- ── Setup: a provider + two users to use as members ──────────────────────────
select * from auth.ensure_provider('examples', 1, 'ex04', 'aad', 'Azure Active Directory',
                                   _allows_group_mapping := true);
select * from auth.ensure_user_from_provider('examples', 1, 'ex04',
        _provider_code := 'aad', _provider_uid := 'hawk-001', _provider_oid := 'oid-hawk-001',
        _username := 'tommy.hawk@twinpeaks.com', _display_name := 'Deputy Hawk',
        _email := 'tommy.hawk@twinpeaks.com');
select * from auth.ensure_user_from_provider('examples', 1, 'ex04',
        _provider_code := 'aad', _provider_uid := 'andy-002', _provider_oid := 'oid-andy-002',
        _username := 'andy.brennan@twinpeaks.com', _display_name := 'Andy Brennan',
        _email := 'andy.brennan@twinpeaks.com');


-- ── Aspect: internal group with explicit members ─────────────────────────────
select * from auth.create_user_group('examples', 1, 'ex04', 'Sheriff Department');

select * from auth.create_user_group_member('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1),
        (select user_id from auth.user_info where email = 'tommy.hawk@twinpeaks.com'));
select * from auth.create_user_group_member('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1),
        (select user_id from auth.user_info where email = 'andy.brennan@twinpeaks.com'));

select * from auth.get_user_group_members('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1));


-- ── Aspect: external group — membership comes only from a provider mapping ────
-- Anyone whose 'aad' identity carries group 'aad-bookhouse' is a member at login,
-- without ever being added here.
select * from auth.create_external_user_group('examples', 1, 'ex04',
        _title := 'Bookhouse Boys (AAD)', _provider_code := 'aad',
        _mapped_object_id := 'aad-bookhouse', _mapped_object_name := 'Bookhouse Boys');

select user_group_id, title, is_external
from auth.user_group where title = 'Bookhouse Boys (AAD)' and tenant_id = 1;


-- ── Aspect: add another mapping (map a provider ROLE too) ─────────────────────
select * from auth.create_user_group_mapping('examples', 1, 'ex04',
        _user_group_id := (select user_group_id from auth.user_group where title = 'Bookhouse Boys (AAD)' and tenant_id = 1),
        _provider_code := 'aad', _mapped_role := 'bookhouse-lead');

select * from auth.get_user_group_mappings('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Bookhouse Boys (AAD)' and tenant_id = 1));


-- ── Aspect: hybrid — promote the internal group so it also honours mappings ──
select auth.set_user_group_as_hybrid('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1));
select * from auth.create_user_group_mapping('examples', 1, 'ex04',
        _user_group_id := (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1),
        _provider_code := 'aad', _mapped_object_id := 'aad-deputies');


-- ── Aspect: remove a direct member ───────────────────────────────────────────
select auth.delete_user_group_member('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1),
        (select user_id from auth.user_info where email = 'andy.brennan@twinpeaks.com'));

select * from auth.get_user_group_members('examples', 1, 'ex04',
        (select user_group_id from auth.user_group where title = 'Sheriff Department' and tenant_id = 1));
