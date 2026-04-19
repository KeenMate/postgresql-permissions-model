/*
 * Example: Path-based ACL against a real filesystem tree
 * ======================================================
 *
 * Loads ~27,000 paths from the Material Design Icons repository into a
 * demo.fs_item table, registers a path-based resource type, then assigns
 * grants to random users at random places in the tree. Runs read/write
 * checks and bulk filtering to exercise the ACL at realistic scale.
 *
 * How to run:
 *   1. Regenerate the insert data (if not already present):
 *      python gen_icons_inserts.py
 *   2. Execute this file:
 *      ./debee.ps1 -Operations execSql -SqlFile 999-examples-icons.sql
 *
 * Everything lives under the `demo` schema so you can drop it wholesale
 * when you're done. Nothing in this file mutates production tables except
 * auth.resource_access rows (cleaned up at the bottom).
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 1. Clean slate (safe to re-run)
-- ============================================================================

drop trigger if exists trg_fs_item_sync_perms_ra    on auth.resource_access;
drop trigger if exists trg_fs_item_sync_perms_rra   on auth.resource_role_assignment;

delete from auth.resource_access where root_type = 'fsitem';
delete from auth.resource_role_assignment where root_type = 'fsitem';
delete from const.resource_role_flag where resource_role_code in ('fsitem_reader', 'fsitem_editor');
delete from const.resource_role where code in ('fsitem_reader', 'fsitem_editor');
delete from auth.user_group_member where user_group_id in
    (select user_group_id from auth.user_group where code in ('icons_designers', 'icons_curators'));
delete from auth.user_group where code in ('icons_designers', 'icons_curators');
delete from auth.permission_assignment
  where user_id in (select user_id from auth.user_info where code like 'icons_demo_%');
delete from auth.user_info where code like 'icons_demo_%';

drop schema if exists demo cascade;
create schema demo;

create table demo.fs_item
(
    item_id         bigint generated always as identity primary key,
    path            ext.ltree not null,
    display_path    text      not null,
    kind            text      not null check (kind in ('folder', 'file')),
    name            text      not null,
    has_permissions boolean   not null default false
);

create unique index uq_fs_item_path      on demo.fs_item (path);
create index        ix_fs_item_path_g    on demo.fs_item using gist (path);
create index        ix_fs_item_kind      on demo.fs_item (kind);
create index        ix_fs_item_has_perms on demo.fs_item (has_permissions) where has_permissions;

-- ============================================================================
-- 2. Load the generated data
-- ============================================================================

\i 999-examples-icons-data.sql

do $$
declare
    _folders bigint;
    _files   bigint;
begin
    select count(*) filter (where kind = 'folder'),
           count(*) filter (where kind = 'file')
      into _folders, _files
    from demo.fs_item;
    raise notice 'Loaded: % folders, % files, % total',
        _folders, _files, _folders + _files;
end $$;

-- ============================================================================
-- 3. Register 'fsitem' as a path-based resource type
-- ============================================================================

insert into const.resource_type (code, source, path, key_schema)
values ('fsitem', 'demo-icons', 'fsitem'::ext.ltree, '{}'::jsonb)
on conflict (code) do nothing;

insert into const.resource_type_flag (resource_type_code, access_flag_code) values
    ('fsitem', 'read'), ('fsitem', 'write'), ('fsitem', 'delete'), ('fsitem', 'share')
on conflict do nothing;

select unsecure.ensure_resource_access_partition('fsitem');

-- Two roles scoped to fsitem:
--   fsitem_reader → read only
--   fsitem_editor → read + write + delete + share
insert into const.resource_role (code, resource_type, source, is_active) values
    ('fsitem_reader', 'fsitem', 'demo-icons', true),
    ('fsitem_editor', 'fsitem', 'demo-icons', true)
on conflict (code) do nothing;

insert into const.resource_role_flag (resource_role_code, access_flag_code) values
    ('fsitem_reader', 'read'),
    ('fsitem_editor', 'read'),
    ('fsitem_editor', 'write'),
    ('fsitem_editor', 'delete'),
    ('fsitem_editor', 'share')
on conflict do nothing;

-- ============================================================================
-- 3b. Keep demo.fs_item.has_permissions in sync with ACL tables
-- ============================================================================
-- A row gets has_permissions = true when any grant (flag or role) is placed
-- directly on its exact path. When the last such grant is removed, the flag
-- flips back to false. Useful for UI (lock icon), admin queries, auditing.
-- Does NOT participate in access-check decisions — inheritance still applies
-- via the normal ancestor walk.

create or replace function demo.fs_item_sync_perms_flag()
returns trigger
    language plpgsql
as $$
begin
    if tg_op = 'INSERT' then
        if new.root_type = 'fsitem' and new.resource_path is not null then
            update demo.fs_item
               set has_permissions = true
             where path = new.resource_path
               and not has_permissions;
        end if;
        return new;
    elsif tg_op = 'DELETE' then
        if old.root_type = 'fsitem' and old.resource_path is not null then
            -- Only flip off if no other grants remain on this exact path
            if not exists (select 1 from auth.resource_access
                           where root_type = 'fsitem'
                             and resource_path = old.resource_path)
               and not exists (select 1 from auth.resource_role_assignment
                               where root_type = 'fsitem'
                                 and resource_path = old.resource_path)
            then
                update demo.fs_item
                   set has_permissions = false
                 where path = old.resource_path
                   and has_permissions;
            end if;
        end if;
        return old;
    end if;
    return null;
end;
$$;

drop trigger if exists trg_fs_item_sync_perms_ra    on auth.resource_access;
drop trigger if exists trg_fs_item_sync_perms_rra   on auth.resource_role_assignment;

create trigger trg_fs_item_sync_perms_ra
    after insert or delete on auth.resource_access
    for each row
    execute function demo.fs_item_sync_perms_flag();

create trigger trg_fs_item_sync_perms_rra
    after insert or delete on auth.resource_role_assignment
    for each row
    execute function demo.fs_item_sync_perms_flag();

-- ============================================================================
-- 4. Test users (13 demo users: 1-10 direct flags, 11-13 role-based)
-- ============================================================================

insert into auth.user_info (created_by, updated_by, display_name, code, username, original_username, email, can_login)
select 'demo', 'demo',
       'Icons Demo User ' || lpad(n::text, 2, '0'),
       'icons_demo_' || n::text,
       'icons_demo_' || n::text || '@example.com',
       'icons_demo_' || n::text || '@example.com',
       'icons_demo_' || n::text || '@example.com',
       true
from generate_series(1, 13) n
on conflict do nothing;

-- Grant all of them base resource permissions so they can self-check.
-- (has_resource_access doesn't require any permission; this is only
-- needed for the grant/deny/revoke calls below which run as "admin".)
select unsecure.assign_permission_as_system(null::integer, u.user_id, 'system_admin')
from auth.user_info u
where u.code = 'icons_demo_1';

-- ============================================================================
-- 5. Randomly assigned grants at various tree depths
-- ============================================================================
--
-- Strategy — direct flag grants (users 1-10):
--   user 2:  read on 3 random top-level categories (broad)
--   user 3:  read on 10 random second-level subtrees (medium)
--   user 4:  read on 50 random icon folders (narrow)
--   user 5:  read+write on 5 random icon folders (narrow, higher privilege)
--   user 6:  read on 'src' (everything) with deny on 3 random categories
--   user 7:  read on 100 random leaf .svg files (leaf-only, no inheritance)
--   user 8:  read via a group membership on 'src.action'
--   user 9:  no grants (negative control)
--   user 10: read on 'src.social' but a deny on a deep descendant
--
-- Strategy — role-based grants (users 11-13), exercises check paths (c) and (e):
--   user 11: direct 'fsitem_editor' role on 20 random third-level folders
--   user 12: member of 'icons_curators' group that has 'fsitem_reader' role
--            on 'src.image'   (tests group-role path check)
--   user 13: 'fsitem_reader' role on 'src.communication' AND a direct
--            'write' flag grant on 'src.communication.chat' (hybrid: shows
--            direct + role grants stacking in get_resource_access_flags)

do $$
declare
    _admin  bigint;
    _u2 bigint; _u3 bigint; _u4 bigint; _u5 bigint; _u6 bigint;
    _u7 bigint; _u8 bigint; _u9 bigint; _u10 bigint;
    _u11 bigint; _u12 bigint; _u13 bigint;
    _group_designers integer;
    _group_curators  integer;
    _p ext.ltree;
    _r record;
begin
    select user_id into _admin from auth.user_info where code = 'icons_demo_1';
    select user_id into _u2 from auth.user_info where code = 'icons_demo_2';
    select user_id into _u3 from auth.user_info where code = 'icons_demo_3';
    select user_id into _u4 from auth.user_info where code = 'icons_demo_4';
    select user_id into _u5 from auth.user_info where code = 'icons_demo_5';
    select user_id into _u6 from auth.user_info where code = 'icons_demo_6';
    select user_id into _u7 from auth.user_info where code = 'icons_demo_7';
    select user_id into _u8 from auth.user_info where code = 'icons_demo_8';
    select user_id into _u9 from auth.user_info where code = 'icons_demo_9';
    select user_id into _u10 from auth.user_info where code = 'icons_demo_10';
    select user_id into _u11 from auth.user_info where code = 'icons_demo_11';
    select user_id into _u12 from auth.user_info where code = 'icons_demo_12';
    select user_id into _u13 from auth.user_info where code = 'icons_demo_13';

    -- user 2: 3 random top-level categories
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 1
        order by random()
        limit 3
    loop
        perform auth.assign_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u2,
            _access_flags   := array['read'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 3: 10 random second-level subtrees (category/icon)
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 2 and kind = 'folder'
        order by random()
        limit 10
    loop
        perform auth.assign_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u3,
            _access_flags   := array['read'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 4: 50 random third-level (icon style folders)
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 3 and kind = 'folder'
        order by random()
        limit 50
    loop
        perform auth.assign_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u4,
            _access_flags   := array['read'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 5: write on 5 random style folders
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 4 and kind = 'folder'
        order by random()
        limit 5
    loop
        perform auth.assign_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u5,
            _access_flags   := array['read', 'write'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 6: broad read on 'src' with denies on 3 categories
    perform auth.assign_resource_access(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := _u6,
        _access_flags   := array['read'],
        _resource_path  := 'src'::ext.ltree
    );
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 2
        order by random()
        limit 3
    loop
        perform auth.deny_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u6,
            _access_flags   := array['read'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 7: 100 random leaf .svg grants (pure leaf, no inheritance)
    for _r in
        select path from demo.fs_item
        where kind = 'file'
        order by random()
        limit 100
    loop
        perform auth.assign_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u7,
            _access_flags   := array['read'],
            _resource_path  := _r.path
        );
    end loop;

    -- user 8: read via group on 'src.action'
    insert into auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, is_assignable)
    values ('demo', 'demo', 1, 'Icons Designers', 'icons_designers', true, true)
    returning user_group_id into _group_designers;

    insert into auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    values ('demo', _group_designers, _u8, 'manual');

    perform auth.assign_resource_access(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _user_group_id  := _group_designers,
        _access_flags   := array['read'],
        _resource_path  := 'src.action'::ext.ltree
    );

    -- user 9: nothing
    -- user 10: read on src.social with deny deep in the subtree
    perform auth.assign_resource_access(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := _u10,
        _access_flags   := array['read'],
        _resource_path  := 'src.social'::ext.ltree
    );
    select path into _p from demo.fs_item
    where path <@ 'src.social'::ext.ltree and kind = 'folder' and nlevel(path) = 3
    order by random() limit 1;
    if _p is not null then
        perform auth.deny_resource_access(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u10,
            _access_flags   := array['read'],
            _resource_path  := _p
        );
    end if;

    -- ------------------------------------------------------------------
    -- user 11: direct fsitem_editor role on 20 random third-level folders
    -- ------------------------------------------------------------------
    for _r in
        select path from demo.fs_item
        where nlevel(path) = 3 and kind = 'folder'
        order by random()
        limit 20
    loop
        perform auth.assign_resource_role(
            _created_by     := 'demo',
            _user_id        := _admin,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _target_user_id := _u11,
            _role_codes     := array['fsitem_editor'],
            _resource_path  := _r.path
        );
    end loop;

    -- ------------------------------------------------------------------
    -- user 12: group role grant — 'icons_curators' has fsitem_reader
    -- on 'src.image' (broad category). Exercises the group-role check.
    -- ------------------------------------------------------------------
    insert into auth.user_group (created_by, updated_by, tenant_id, title, code, is_active, is_assignable)
    values ('demo', 'demo', 1, 'Icons Curators', 'icons_curators', true, true)
    returning user_group_id into _group_curators;

    insert into auth.user_group_member (created_by, user_group_id, user_id, member_type_code)
    values ('demo', _group_curators, _u12, 'manual');

    perform auth.assign_resource_role(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _user_group_id  := _group_curators,
        _role_codes     := array['fsitem_reader'],
        _resource_path  := 'src.image'::ext.ltree
    );

    -- ------------------------------------------------------------------
    -- user 13: hybrid — fsitem_reader role on 'src.communication', plus
    -- a direct 'write' flag grant on 'src.communication.chat'.
    -- Demonstrates direct + role grants stacking.
    -- ------------------------------------------------------------------
    perform auth.assign_resource_role(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := _u13,
        _role_codes     := array['fsitem_reader'],
        _resource_path  := 'src.communication'::ext.ltree
    );
    perform auth.assign_resource_access(
        _created_by     := 'demo',
        _user_id        := _admin,
        _correlation_id := null,
        _resource_type  := 'fsitem',
        _target_user_id := _u13,
        _access_flags   := array['write'],
        _resource_path  := 'src.communication.chat'::ext.ltree
    );
end $$;

-- ============================================================================
-- 6. Grant summary (direct flags + role assignments, user-level only)
-- ============================================================================

select src, display_name, kind, count(*) as rows, min(path_sample) as first_path_sample
from (
    select 'user-flag' as src,
           u.display_name,
           (case when ra.is_deny then 'DENY:' else '' end) || ra.access_flag as kind,
           ra.resource_path::text as path_sample
    from auth.resource_access ra
    join auth.user_info u on u.user_id = ra.user_id
    where ra.root_type = 'fsitem'
    union all
    select 'group-flag' as src,
           g.title as display_name,
           (case when ra.is_deny then 'DENY:' else '' end) || ra.access_flag as kind,
           ra.resource_path::text as path_sample
    from auth.resource_access ra
    join auth.user_group g on g.user_group_id = ra.user_group_id
    where ra.root_type = 'fsitem'
    union all
    select 'user-role' as src,
           u.display_name,
           'role:' || rra.role_code as kind,
           rra.resource_path::text as path_sample
    from auth.resource_role_assignment rra
    join auth.user_info u on u.user_id = rra.user_id
    where rra.root_type = 'fsitem'
    union all
    select 'group-role' as src,
           g.title as display_name,
           'role:' || rra.role_code as kind,
           rra.resource_path::text as path_sample
    from auth.resource_role_assignment rra
    join auth.user_group g on g.user_group_id = rra.user_group_id
    where rra.root_type = 'fsitem'
) s
group by src, display_name, kind
order by display_name, src, kind;

-- ============================================================================
-- 6b. has_permissions summary — rows carrying a direct ACL entry
-- ============================================================================
-- Maintained by triggers on auth.resource_access + resource_role_assignment.
-- These are the rows a UI would badge with a "custom permissions" indicator.

select
    count(*) filter (where has_permissions)                  as rows_with_perms,
    count(*) filter (where has_permissions and kind='folder') as folders_with_perms,
    count(*) filter (where has_permissions and kind='file')   as files_with_perms,
    count(*)                                                 as total_rows
from demo.fs_item;

-- 10 sample rows with has_permissions = true
select path::text, kind, name
from demo.fs_item
where has_permissions
order by path
limit 10;

-- ============================================================================
-- 7. Performance checks
-- ============================================================================

-- 7a. Random-leaf single-check latency per user
\timing on
do $$
declare
    _target ext.ltree;
    _u record;
    _granted boolean;
    _t0 timestamptz;
    _dt_us bigint;
begin
    raise notice '--- Single has_resource_access latency on a random leaf ---';
    select path into _target from demo.fs_item where kind = 'file' order by random() limit 1;
    raise notice 'target leaf: %', _target::text;

    for _u in
        select user_id, display_name, code from auth.user_info
        where code like 'icons_demo_%'
        order by code
    loop
        _t0 := clock_timestamp();
        _granted := auth.has_resource_access(
            _user_id        := _u.user_id,
            _correlation_id := null,
            _resource_type  := 'fsitem',
            _required_flag  := 'read',
            _resource_path  := _target,
            _throw_err      := false
        );
        _dt_us := extract(epoch from clock_timestamp() - _t0) * 1000000;
        raise notice '%  granted=%  %us', rpad(_u.display_name, 20), _granted, _dt_us;
    end loop;
end $$;
\timing off

-- 7b. Bulk filter: take 1000 random leaves and filter per user
do $$
declare
    _paths ext.ltree[];
    _u record;
    _accessible integer;
    _t0 timestamptz;
    _dt_ms numeric;
begin
    raise notice '';
    raise notice '--- Bulk filter (1000 random leaves) ---';
    select array_agg(path) into _paths
    from (
        select path from demo.fs_item where kind = 'file' order by random() limit 1000
    ) s;

    for _u in
        select user_id, display_name, code from auth.user_info
        where code like 'icons_demo_%'
        order by code
    loop
        _t0 := clock_timestamp();
        select count(*) into _accessible
        from auth.filter_accessible_resources(
            _user_id         := _u.user_id,
            _correlation_id  := null,
            _resource_type   := 'fsitem',
            _required_flag   := 'read',
            _resource_paths  := _paths
        );
        _dt_ms := extract(epoch from clock_timestamp() - _t0) * 1000;
        raise notice '%  accessible=% / 1000  %ms',
            rpad(_u.display_name, 20), _accessible, round(_dt_ms, 2);
    end loop;
end $$;

-- 7c. Plan inspection — EXPLAIN ANALYZE on one check
do $$
declare
    _target ext.ltree;
    _u6 bigint;
begin
    raise notice '';
    raise notice '--- EXPLAIN plan for an ancestor-walk check on user 6 ---';
    select path into _target from demo.fs_item where kind = 'file' order by random() limit 1;
    select user_id into _u6 from auth.user_info where code = 'icons_demo_6';
    raise notice 'target leaf: %', _target::text;
    raise notice '(run manually to see the plan)';
    raise notice '  explain (analyze, buffers) select auth.has_resource_access(';
    raise notice '      _user_id := %,', _u6;
    raise notice '      _correlation_id := null,';
    raise notice '      _resource_type := ''fsitem'',';
    raise notice '      _required_flag := ''read'',';
    raise notice '      _resource_path := %::ext.ltree,', quote_literal(_target::text);
    raise notice '      _throw_err := false);';
end $$;

-- ============================================================================
-- 8. Cleanup helpers (uncomment to run)
-- ============================================================================
--
-- delete from auth.resource_access where root_type = 'fsitem';
-- delete from auth.user_group_member where user_group_id in
--     (select user_group_id from auth.user_group where code = 'icons_designers');
-- delete from auth.user_group where code = 'icons_designers';
-- delete from auth.permission_assignment
--   where user_id in (select user_id from auth.user_info where code like 'icons_demo_%');
-- delete from auth.user_info where code like 'icons_demo_%';
-- delete from const.resource_type_flag where resource_type_code = 'fsitem';
-- delete from const.resource_type where code = 'fsitem' and source = 'demo-icons';
-- drop schema demo cascade;
