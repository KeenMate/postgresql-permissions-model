/*
 * Organiogram Example — Resource Roles Demo
 * ==========================================
 *
 * Demonstrates resource roles on an organization tree:
 *   - public.organization table with ltree hierarchy
 *   - 30 org nodes across 4 levels
 *   - 5 users with different access patterns
 *   - org_reader / org_writer resource roles + assign_manager flag
 *
 * Users:
 *   Alice  (CEO)        — org_writer on entire company
 *   Bob    (VP Eng)     — org_reader on company, org_writer on engineering
 *   Charlie (Tech Lead) — org_writer on backend + qa (two branches)
 *   Diana  (Product)    — org_writer on product.design, org_reader on product
 *   Eve    (HR Admin)   — org_writer on hr, deny assign_manager on hr.benefits
 *
 * Run:  ./debee.ps1 -Operations execSql -SqlFile 999-examples-organiogram.sql
 *       ./debee.sh -o execSql --sql-file 999-examples-organiogram.sql
 *
 * Everything runs in a transaction and rolls back at the end so nothing persists.
 */

begin;

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 1. Create the organization table
-- ============================================================================
create table if not exists public.organization (
    org_id    bigint generated always as identity primary key,
    title     text not null,
    node_path ext.ltree not null unique,
    is_active boolean not null default true
);

create index if not exists ix_org_path on public.organization using gist (node_path);

\echo ''
\echo '=== 1. Organization table created ==='

-- ============================================================================
-- 2. Insert 30 org nodes
-- ============================================================================
insert into public.organization (title, node_path) values
    -- Level 0: root
    ('Company',            'company'),

    -- Level 1: divisions
    ('Engineering',        'company.engineering'),
    ('Product',            'company.product'),
    ('Sales',              'company.sales'),
    ('Human Resources',    'company.hr'),
    ('Finance',            'company.finance'),

    -- Level 2: departments under Engineering
    ('Backend',            'company.engineering.backend'),
    ('Frontend',           'company.engineering.frontend'),
    ('QA',                 'company.engineering.qa'),

    -- Level 3: teams under Engineering
    ('API Team',           'company.engineering.backend.api'),
    ('Data Team',          'company.engineering.backend.data'),
    ('Infrastructure',     'company.engineering.backend.infra'),
    ('Web',                'company.engineering.frontend.web'),
    ('Mobile',             'company.engineering.frontend.mobile'),
    ('Manual Testing',     'company.engineering.qa.manual'),
    ('Automation',         'company.engineering.qa.automation'),

    -- Level 2: departments under Product
    ('Design',             'company.product.design'),
    ('Product Management', 'company.product.management'),
    ('Analytics',          'company.product.analytics'),

    -- Level 3: teams under Product > Design
    ('UX',                 'company.product.design.ux'),
    ('UI',                 'company.product.design.ui'),

    -- Level 2: departments under Sales
    ('Enterprise Sales',   'company.sales.enterprise'),
    ('SMB Sales',          'company.sales.smb'),
    ('Partnerships',       'company.sales.partnerships'),

    -- Level 2: departments under HR
    ('Recruiting',         'company.hr.recruiting'),
    ('Benefits',           'company.hr.benefits'),
    ('Training',           'company.hr.training'),

    -- Level 2: departments under Finance
    ('Accounting',         'company.finance.accounting'),
    ('Payroll',            'company.finance.payroll'),
    ('Procurement',        'company.finance.procurement');

\echo '=== 2. Inserted 30 org nodes ==='

select org_id, title, node_path from public.organization order by node_path;

-- ============================================================================
-- 3. Create test users
-- ============================================================================
do $$
declare
    _alice_id   bigint;
    _bob_id     bigint;
    _charlie_id bigint;
    _diana_id   bigint;
    _eve_id     bigint;
begin
    insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    values ('demo', 'demo', 'Alice (CEO)',        'alice_ceo',       'alice@example.com', 'alice@example.com', 'alice@example.com', true)
    returning user_id into _alice_id;

    insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    values ('demo', 'demo', 'Bob (VP Eng)',       'bob_vp_eng',      'bob@example.com',   'bob@example.com',   'bob@example.com', true)
    returning user_id into _bob_id;

    insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    values ('demo', 'demo', 'Charlie (Tech Lead)','charlie_techlead','charlie@example.com','charlie@example.com','charlie@example.com', true)
    returning user_id into _charlie_id;

    insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    values ('demo', 'demo', 'Diana (Product)',    'diana_product',   'diana@example.com', 'diana@example.com', 'diana@example.com', true)
    returning user_id into _diana_id;

    insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
    values ('demo', 'demo', 'Eve (HR Admin)',     'eve_hr_admin',    'eve@example.com',   'eve@example.com',   'eve@example.com', true)
    returning user_id into _eve_id;

    -- Store IDs for later use
    create temp table _demo_users (name text primary key, uid bigint);
    insert into _demo_users values
        ('alice', _alice_id), ('bob', _bob_id), ('charlie', _charlie_id),
        ('diana', _diana_id), ('eve', _eve_id);

    raise notice '';
    raise notice '=== 3. Users created: alice=%, bob=%, charlie=%, diana=%, eve=% ===',
        _alice_id, _bob_id, _charlie_id, _diana_id, _eve_id;
end $$;

-- ============================================================================
-- 4. Register resource type, flags, and roles
-- ============================================================================

-- Custom access flag + translation
insert into const.resource_access_flag (code, source)
values ('assign_manager', 'organiogram')
on conflict do nothing;

insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
values ('demo', 'demo', 'en', 'resource_access_flag', 'assign_manager', 'title', 'Assign Manager')
on conflict do nothing;

-- Resource type + translations
insert into const.resource_type (code, source, path, key_schema)
values ('org_unit', 'organiogram', 'org_unit'::ext.ltree, '{"org_id": "bigint"}'::jsonb)
on conflict do nothing;

insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    ('demo', 'demo', 'en', 'resource_type', 'org_unit', 'title',       'Organization Unit'),
    ('demo', 'demo', 'en', 'resource_type', 'org_unit', 'description', 'A node in the organization tree')
on conflict do nothing;

-- Per-type flags
insert into const.resource_type_flag (resource_type_code, access_flag_code) values
    ('org_unit', 'read'),
    ('org_unit', 'write'),
    ('org_unit', 'assign_manager')
on conflict do nothing;

-- Partition
select unsecure.ensure_resource_access_partition('org_unit');

-- Resource roles + translations
insert into const.resource_role (code, resource_type, source) values
    ('org_reader', 'org_unit', 'organiogram'),
    ('org_writer', 'org_unit', 'organiogram')
on conflict do nothing;

insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    ('demo', 'demo', 'en', 'resource_role', 'org_reader', 'title',       'Reader'),
    ('demo', 'demo', 'en', 'resource_role', 'org_reader', 'description', 'Read-only access to an org unit'),
    ('demo', 'demo', 'en', 'resource_role', 'org_writer', 'title',       'Writer/Admin'),
    ('demo', 'demo', 'en', 'resource_role', 'org_writer', 'description', 'Full access including manager assignment')
on conflict do nothing;

insert into const.resource_role_flag (resource_role_code, access_flag_code) values
    ('org_reader', 'read'),
    ('org_writer', 'read'),
    ('org_writer', 'write'),
    ('org_writer', 'assign_manager')
on conflict do nothing;

-- Refresh MV so reads pick up the translations we just inserted
select internal.refresh_translation_cache();

\echo '=== 4. Resource type, flags, roles registered ==='

select * from auth.get_resource_roles(_resource_type := 'org_unit');

-- ============================================================================
-- 5. Assign roles to users
-- ============================================================================
-- For each user, we assign roles on specific org nodes.
-- Since org_unit is a flat resource type (no type hierarchy), access does NOT
-- auto-cascade to child nodes. The application must either:
--   a) Assign at each relevant node, OR
--   b) Query filter_accessible_resources + join with ltree descendant logic
--
-- Here we assign at each node to keep the demo self-contained.

do $$
declare
    _alice   bigint; _bob bigint; _charlie bigint; _diana bigint; _eve bigint;
    _org     record;
begin
    select uid from _demo_users where name = 'alice'   into _alice;
    select uid from _demo_users where name = 'bob'     into _bob;
    select uid from _demo_users where name = 'charlie' into _charlie;
    select uid from _demo_users where name = 'diana'   into _diana;
    select uid from _demo_users where name = 'eve'     into _eve;

    -- -----------------------------------------------------------------------
    -- ALICE (CEO): org_writer on ALL 30 nodes
    -- -----------------------------------------------------------------------
    for _org in select org_id from public.organization loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _alice, 'org_writer', _alice
        );
    end loop;
    raise notice 'Alice: org_writer on all 30 nodes';

    -- -----------------------------------------------------------------------
    -- BOB (VP Eng): org_reader on entire company, org_writer on engineering branch
    -- -----------------------------------------------------------------------
    -- Reader on everything outside engineering
    for _org in
        select org_id from public.organization
        where node_path <@ 'company'::ext.ltree
          and not (node_path <@ 'company.engineering'::ext.ltree)
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _bob, 'org_reader', _alice
        );
    end loop;
    -- Writer on engineering and descendants
    for _org in
        select org_id from public.organization
        where node_path <@ 'company.engineering'::ext.ltree
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _bob, 'org_writer', _alice
        );
    end loop;
    raise notice 'Bob: org_reader on company (non-eng), org_writer on engineering branch';

    -- -----------------------------------------------------------------------
    -- CHARLIE (Tech Lead): org_writer on backend + qa branches only
    -- -----------------------------------------------------------------------
    for _org in
        select org_id from public.organization
        where node_path <@ 'company.engineering.backend'::ext.ltree
           or node_path <@ 'company.engineering.qa'::ext.ltree
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _charlie, 'org_writer', _bob
        );
    end loop;
    raise notice 'Charlie: org_writer on backend + qa branches';

    -- -----------------------------------------------------------------------
    -- DIANA (Product): org_reader on product, org_writer on product.design
    -- -----------------------------------------------------------------------
    -- Reader on product (non-design)
    for _org in
        select org_id from public.organization
        where node_path <@ 'company.product'::ext.ltree
          and not (node_path <@ 'company.product.design'::ext.ltree)
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _diana, 'org_reader', _alice
        );
    end loop;
    -- Writer on design branch
    for _org in
        select org_id from public.organization
        where node_path <@ 'company.product.design'::ext.ltree
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _diana, 'org_writer', _alice
        );
    end loop;
    raise notice 'Diana: org_reader on product, org_writer on product.design';

    -- -----------------------------------------------------------------------
    -- EVE (HR Admin): org_writer on HR, but DENY assign_manager on Benefits
    -- -----------------------------------------------------------------------
    for _org in
        select org_id from public.organization
        where node_path <@ 'company.hr'::ext.ltree
    loop
        insert into auth.resource_role_assignment (
            created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
            user_id, role_code, granted_by
        ) values (
            'demo', 'demo', 1, 'org_unit', 'org_unit',
            jsonb_build_object('org_id', _org.org_id),
            _eve, 'org_writer', _alice
        );
    end loop;
    -- Deny assign_manager on Benefits (org_id = 26)
    insert into auth.resource_access (
        created_by, updated_by, tenant_id, resource_type, root_type, resource_id,
        user_id, access_flag, is_deny, granted_by
    ) values (
        'demo', 'demo', 1, 'org_unit', 'org_unit',
        (select jsonb_build_object('org_id', org_id) from public.organization where title = 'Benefits'),
        _eve, 'assign_manager', true, _alice
    );
    raise notice 'Eve: org_writer on hr, DENY assign_manager on Benefits';

    raise notice '';
    raise notice '=== 5. Roles assigned ===';
end $$;

-- ============================================================================
-- 6. Queries — Who can do what?
-- ============================================================================

\echo ''
\echo '=== 6. Translations for resource_type via get_group_translations ==='
select public.get_group_translations('en', 'resource_type');

\echo ''
\echo '=== 6a. All role assignments (role-level view) ==='
select
    ui.display_name as "User",
    o.title as "Org Unit",
    o.node_path::text as "Path",
    rra.role_code as "Role",
    t_role.value as "Role Title"
from auth.resource_role_assignment rra
inner join auth.user_info ui on ui.user_id = rra.user_id
inner join public.organization o on o.org_id = (rra.resource_id->>'org_id')::bigint
left join public.translation t_role
    on t_role.data_group = 'resource_role' and t_role.data_object_code = rra.role_code
    and t_role.context = 'title' and t_role.language_code = 'en'
where rra.resource_type = 'org_unit'
order by ui.display_name, o.node_path;

\echo ''
\echo '=== 6b. Deny rules ==='
select
    ui.display_name as "User",
    o.title as "Org Unit",
    ra.access_flag as "Denied Flag"
from auth.resource_access ra
inner join auth.user_info ui on ui.user_id = ra.user_id
inner join public.organization o on o.org_id = (ra.resource_id->>'org_id')::bigint
where ra.resource_type = 'org_unit' and ra.is_deny = true
order by ui.display_name;

\echo ''
\echo '=== 6c. Access check: Can each user WRITE to each division? ==='
select
    ui.display_name as "User",
    o.title as "Division",
    auth.has_resource_access(
        ui.user_id, 'demo', 'org_unit',
        jsonb_build_object('org_id', o.org_id),
        'write', 1, false
    ) as "can_write"
from auth.user_info ui
cross join public.organization o
where ui.code in ('alice_ceo','bob_vp_eng','charlie_techlead','diana_product','eve_hr_admin')
  and ext.nlevel(o.node_path) = 2  -- level-1 divisions only
order by ui.display_name, o.title;

\echo ''
\echo '=== 6d. Access check: Can each user ASSIGN_MANAGER in HR? ==='
select
    ui.display_name as "User",
    o.title as "HR Unit",
    auth.has_resource_access(
        ui.user_id, 'demo', 'org_unit',
        jsonb_build_object('org_id', o.org_id),
        'assign_manager', 1, false
    ) as "can_assign_mgr"
from auth.user_info ui
cross join public.organization o
where ui.code in ('alice_ceo','eve_hr_admin')
  and o.node_path <@ 'company.hr'::ext.ltree
order by ui.display_name, o.node_path;

\echo ''
\echo '=== 6e. Effective flags per user on Engineering > Backend ==='
select
    ui.display_name as "User",
    f.__access_flag as "Flag",
    f.__source as "Source"
from auth.user_info ui
cross join lateral auth.get_resource_access_flags(
    ui.user_id, 'demo', 'org_unit',
    (select jsonb_build_object('org_id', org_id)
     from public.organization where title = 'Backend')
) f
where ui.code in ('alice_ceo','bob_vp_eng','charlie_techlead','diana_product','eve_hr_admin')
order by ui.display_name, f.__access_flag;

\echo ''
\echo '=== 6f. Charlie: which org units can he write? ==='
select
    o.title as "Org Unit",
    o.node_path::text as "Path"
from public.organization o
where auth.has_resource_access(
    (select uid from _demo_users where name = 'charlie'),
    'demo', 'org_unit',
    jsonb_build_object('org_id', o.org_id),
    'write', 1, false
) = true
order by o.node_path;

\echo ''
\echo '=== 6g. Diana: which org units can she access (any flag)? ==='
select
    o.title as "Org Unit",
    o.node_path::text as "Path",
    (select array_agg(f.__access_flag order by f.__access_flag)
     from auth.get_resource_access_flags(
         (select uid from _demo_users where name = 'diana'),
         'demo', 'org_unit',
         jsonb_build_object('org_id', o.org_id)
     ) f
    ) as "Flags"
from public.organization o
where auth.has_resource_access(
    (select uid from _demo_users where name = 'diana'),
    'demo', 'org_unit',
    jsonb_build_object('org_id', o.org_id),
    'read', 1, false
) = true
order by o.node_path;

-- ============================================================================
-- Cleanup: rollback everything
-- ============================================================================
\echo ''
\echo '=== Rolling back — nothing persists ==='

drop table if exists _demo_users;
drop table if exists public.organization cascade;

rollback;
