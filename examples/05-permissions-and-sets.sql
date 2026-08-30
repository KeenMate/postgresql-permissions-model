/*
 * Example 05 — Permissions, permission sets & checks
 * ==================================================
 *
 * Showcases how access is granted and evaluated:
 *   - global hierarchical permissions (ltree: business.orders.*)
 *   - a tenant permission set, and editing its contents
 *   - three ways a user ends up with a permission:
 *       (a) set assigned directly to the user
 *       (b) set assigned to a group the user belongs to (inheritance)
 *       (c) set assigned to an external group resolved from the provider at login
 *
 * Standalone plain SQL — run one statement at a time in any client. Data persists;
 * run examples/cleanup.sql to reset. Acts as the system user (user_id = 1).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;


-- ── Aspect: create a global permission hierarchy ─────────────────────────────
-- full_code is derived from the title: business > business.orders > .create_order
select * from auth.create_permission('examples', 1, 'ex05', 'Business');
select * from auth.create_permission('examples', 1, 'ex05', 'Orders',       _parent_full_code := 'business');
select * from auth.create_permission('examples', 1, 'ex05', 'Create order', _parent_full_code := 'business.orders');
select * from auth.create_permission('examples', 1, 'ex05', 'Cancel order', _parent_full_code := 'business.orders');


-- ── Aspect: create a permission set, then edit its contents ──────────────────
select * from auth.create_perm_set('examples', 1, 'ex05', 'Order Manager',
        _permissions := array['business.orders.create_order']);

-- add cancel_order …
select * from auth.create_perm_set_permissions('examples', 1, 'ex05',
        (select perm_set_id from auth.perm_set where code = helpers.get_code('Order Manager') and tenant_id = 1),
        array['business.orders.cancel_order']);

-- … then remove it again
select * from auth.delete_perm_set_permissions('examples', 1, 'ex05',
        (select perm_set_id from auth.perm_set where code = helpers.get_code('Order Manager') and tenant_id = 1),
        array['business.orders.cancel_order']);


-- ── Aspect (a): assign the set directly to a user, then check access ─────────
select * from auth.register_user('examples', 1, 'ex05',
        _email := 'harry.truman@twinpeaks.com', _password_hash := 'not-a-real-hash',
        _display_name := 'Sheriff Harry Truman');

select * from auth.assign_permission('examples', 1, 'ex05',
        _user_group_id := null,
        _target_user_id := (select user_id from auth.user_info where email = 'harry.truman@twinpeaks.com'),
        _perm_set_code := (select code from auth.perm_set where code = helpers.get_code('Order Manager') and tenant_id = 1),
        _permission_full_code := null);

-- create_order = true (in the set); cancel_order = false (removed above)
select auth.has_permission((select user_id from auth.user_info where email = 'harry.truman@twinpeaks.com'),
           'ex05', 'business.orders.create_order', 1, false) as can_create_order,
       auth.has_permission((select user_id from auth.user_info where email = 'harry.truman@twinpeaks.com'),
           'ex05', 'business.orders.cancel_order', 1, false) as can_cancel_order;

-- effective permissions for the user
select * from auth.get_user_permissions(1, 'ex05',
        (select user_id from auth.user_info where email = 'harry.truman@twinpeaks.com'));


-- ── Aspect (b): assign the set to a group; a member inherits it ──────────────
select * from auth.register_user('examples', 1, 'ex05',
        _email := 'lucy.moran@twinpeaks.com', _password_hash := 'not-a-real-hash',
        _display_name := 'Lucy Moran');

select * from auth.create_user_group('examples', 1, 'ex05', 'Order Desk');
select * from auth.create_user_group_member('examples', 1, 'ex05',
        (select user_group_id from auth.user_group where title = 'Order Desk' and tenant_id = 1),
        (select user_id from auth.user_info where email = 'lucy.moran@twinpeaks.com'));
select * from auth.assign_permission('examples', 1, 'ex05',
        _user_group_id := (select user_group_id from auth.user_group where title = 'Order Desk' and tenant_id = 1),
        _target_user_id := null,
        _perm_set_code := (select code from auth.perm_set where code = helpers.get_code('Order Manager') and tenant_id = 1),
        _permission_full_code := null);

-- Lucy has create_order via the group — expect true
select auth.has_permission((select user_id from auth.user_info where email = 'lucy.moran@twinpeaks.com'),
           'ex05', 'business.orders.create_order', 1, false) as can_create_order;


-- ── Aspect (c): resolve permissions from an external provider group at login ─
select * from auth.ensure_provider('examples', 1, 'ex05', 'aad', 'Azure Active Directory',
                                   _allows_group_mapping := true);
select * from auth.ensure_user_from_provider('examples', 1, 'ex05',
        _provider_code := 'aad', _provider_uid := 'josie-001', _provider_oid := 'oid-josie-001',
        _username := 'josie.packard@twinpeaks.com', _display_name := 'Josie Packard',
        _email := 'josie.packard@twinpeaks.com');

-- external group mapped to aad object 'aad-order-managers', with the set assigned
select * from auth.create_external_user_group('examples', 1, 'ex05',
        _title := 'Order Managers (AAD)', _provider_code := 'aad',
        _mapped_object_id := 'aad-order-managers');
select * from auth.assign_permission('examples', 1, 'ex05',
        _user_group_id := (select user_group_id from auth.user_group where title = 'Order Managers (AAD)' and tenant_id = 1),
        _target_user_id := null,
        _perm_set_code := (select code from auth.perm_set where code = helpers.get_code('Order Manager') and tenant_id = 1),
        _permission_full_code := null);

-- simulate the post-login sync: Josie's aad identity carries 'aad-order-managers'.
-- This resolves membership + permissions and populates auth.user_permission_cache.
select * from auth.ensure_groups_and_permissions('examples', 1, 'ex05',
        (select user_id from auth.user_info where email = 'josie.packard@twinpeaks.com'),
        'aad', array['aad-order-managers']);

-- Josie now passes the check (served from cache) — expect true
select auth.has_permission((select user_id from auth.user_info where email = 'josie.packard@twinpeaks.com'),
           'ex05', 'business.orders.create_order', 1, false) as can_create_order;

-- the cached row backing that decision
select user_id, tenant_id, groups, permissions, expiration_date
from auth.user_permission_cache
where user_id = (select user_id from auth.user_info where email = 'josie.packard@twinpeaks.com');
