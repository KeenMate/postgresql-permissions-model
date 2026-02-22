/*
 * Cache Invalidation + Real-Time Notification Triggers
 * =====================================================
 *
 * This file contains:
 * 1. Trigger functions that fix cache invalidation gaps (triggers.cache_*)
 * 2. Trigger functions that send pg_notify notifications (triggers.notify_*)
 * 3. CREATE TRIGGER statements that attach them to auth.* tables
 *
 * Architecture:
 * - auth.* functions are db-gen generated and MUST NOT be modified
 * - Cache invalidation that couldn't be added to unsecure.* functions
 *   is handled here via AFTER/BEFORE triggers on auth.* tables
 * - All notifications go through unsecure.notify_permission_change()
 *   which calls pg_notify('permission_changes', JSON payload)
 *
 * Companion changes in 019_functions_unsecure.sql:
 * - unsecure.notify_permission_change() — the notification function
 * - unsecure.invalidate_permission_users_cache() — permission-level cache helper
 * - unsecure.invalidate_users_permission_cache() — bulk user cache helper
 * - unsecure.create_user_group_member() — cache invalidation added
 * - unsecure.set_permission_as_assignable() — cache invalidation added
 * - unsecure.update_perm_set() — cache invalidation added on is_assignable change
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- =============================================================================
-- PART 1: CACHE INVALIDATION TRIGGER FUNCTIONS
-- =============================================================================

-- Cache invalidation on user_group_member DELETE
-- Covers: auth.delete_user_group_member(), set_user_group_as_external/internal(), cascade deletes
create or replace function triggers.cache_user_group_member_delete() returns trigger
    language plpgsql
as
$$
begin
    perform unsecure.clear_permission_cache('trigger', OLD.user_id, null);
    return OLD;
end;
$$;

-- Cache invalidation on user_group is_active change (disable/enable)
-- Covers: auth.disable_user_group(), auth.enable_user_group()
create or replace function triggers.cache_user_group_status_change() returns trigger
    language plpgsql
as
$$
begin
    if OLD.is_active is distinct from NEW.is_active then
        perform unsecure.invalidate_group_members_permission_cache(
            'trigger', NEW.user_group_id, NEW.tenant_id);
    end if;
    return NEW;
end;
$$;

-- Cache invalidation BEFORE user_group DELETE (must read members before cascade)
-- Covers: auth.delete_user_group()
create or replace function triggers.cache_user_group_before_delete() returns trigger
    language plpgsql
as
$$
declare
    _affected_user_ids bigint[];
begin
    select array_agg(user_id)
    from auth.user_group_member
    where user_group_id = OLD.user_group_id
    into _affected_user_ids;

    if _affected_user_ids is not null then
        perform unsecure.invalidate_users_permission_cache('trigger', _affected_user_ids, OLD.tenant_id);
    end if;

    return OLD;
end;
$$;

-- Cache invalidation BEFORE provider DELETE (must read user identities before cascade)
-- Covers: auth.delete_provider()
create or replace function triggers.cache_provider_before_delete() returns trigger
    language plpgsql
as
$$
declare
    _affected_user_ids bigint[];
begin
    select array_agg(distinct ui.user_id)
    from auth.user_identity ui
    where ui.provider_code = OLD.code
    into _affected_user_ids;

    if _affected_user_ids is not null then
        perform unsecure.invalidate_users_permission_cache('trigger', _affected_user_ids, null);
    end if;

    return OLD;
end;
$$;

-- Cache invalidation on provider disable
-- Covers: auth.disable_provider()
create or replace function triggers.cache_provider_status_change() returns trigger
    language plpgsql
as
$$
declare
    _affected_user_ids bigint[];
begin
    if OLD.is_active is distinct from NEW.is_active and NEW.is_active = false then
        select array_agg(distinct ui.user_id)
        from auth.user_identity ui
        where ui.provider_code = NEW.code
        into _affected_user_ids;

        if _affected_user_ids is not null then
            perform unsecure.invalidate_users_permission_cache('trigger', _affected_user_ids, null);
        end if;
    end if;

    return NEW;
end;
$$;


-- =============================================================================
-- PART 2: NOTIFICATION TRIGGER FUNCTIONS
-- =============================================================================

-- Notify on permission_assignment changes (INSERT/DELETE)
create or replace function triggers.notify_permission_assignment() returns trigger
    language plpgsql
as
$$
declare
    _row          auth.permission_assignment;
    _event        text;
    _target_type  text;
    _target_id    bigint;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'permission_assigned' else 'permission_unassigned' end;

    if _row.user_id is not null then
        _target_type := 'user';
        _target_id := _row.user_id;
    else
        _target_type := 'group';
        _target_id := _row.user_group_id;
    end if;

    perform unsecure.notify_permission_change(
        _event, _row.tenant_id, _target_type, _target_id,
        jsonb_build_object('perm_set_id', _row.perm_set_id, 'permission_id', _row.permission_id));

    return _row;
end;
$$;

-- Notify on perm_set_perm changes (permissions added/removed from a set)
create or replace function triggers.notify_perm_set_perm() returns trigger
    language plpgsql
as
$$
declare
    _row       auth.perm_set_perm;
    _event     text;
    _tenant_id int;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'perm_set_permissions_added' else 'perm_set_permissions_removed' end;

    select tenant_id from auth.perm_set where perm_set_id = _row.perm_set_id into _tenant_id;

    perform unsecure.notify_permission_change(
        _event, _tenant_id, 'perm_set', _row.perm_set_id,
        jsonb_build_object('permission_id', _row.permission_id));

    return _row;
end;
$$;

-- Notify on user_group_member changes (INSERT/DELETE)
create or replace function triggers.notify_user_group_member() returns trigger
    language plpgsql
as
$$
declare
    _row       auth.user_group_member;
    _event     text;
    _tenant_id int;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'group_member_added' else 'group_member_removed' end;

    select tenant_id from auth.user_group where user_group_id = _row.user_group_id into _tenant_id;

    perform unsecure.notify_permission_change(
        _event, _tenant_id, 'user', _row.user_id,
        jsonb_build_object('group_id', _row.user_group_id));

    return _row;
end;
$$;

-- Notify on user_group status changes (UPDATE) and deletion (BEFORE DELETE)
create or replace function triggers.notify_user_group() returns trigger
    language plpgsql
as
$$
declare
    _event text;
begin
    if TG_OP = 'DELETE' then
        perform unsecure.notify_permission_change(
            'group_deleted', OLD.tenant_id, 'group', OLD.user_group_id, null);
        return OLD;
    end if;

    -- UPDATE cases
    if OLD.is_active is distinct from NEW.is_active then
        _event := case when NEW.is_active then 'group_enabled' else 'group_disabled' end;
        perform unsecure.notify_permission_change(
            _event, NEW.tenant_id, 'group', NEW.user_group_id, null);
    end if;

    if OLD.is_external is distinct from NEW.is_external then
        perform unsecure.notify_permission_change(
            'group_type_changed', NEW.tenant_id, 'group', NEW.user_group_id,
            jsonb_build_object('is_external', NEW.is_external));
    end if;

    return NEW;
end;
$$;

-- Notify on user_group_mapping changes (INSERT/DELETE)
create or replace function triggers.notify_user_group_mapping() returns trigger
    language plpgsql
as
$$
declare
    _row       auth.user_group_mapping;
    _event     text;
    _tenant_id int;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'group_mapping_created' else 'group_mapping_deleted' end;

    select tenant_id from auth.user_group where user_group_id = _row.user_group_id into _tenant_id;

    perform unsecure.notify_permission_change(
        _event, _tenant_id, 'group', _row.user_group_id,
        jsonb_build_object('provider_code', _row.provider_code));

    return _row;
end;
$$;

-- Notify on user_info status changes (is_active, is_locked) and deletion
create or replace function triggers.notify_user_status() returns trigger
    language plpgsql
as
$$
declare
    _event text;
begin
    if TG_OP = 'DELETE' then
        perform unsecure.notify_permission_change(
            'user_deleted', null, 'user', OLD.user_id, null);
        return OLD;
    end if;

    -- UPDATE cases
    if OLD.is_active is distinct from NEW.is_active then
        _event := case when NEW.is_active then 'user_enabled' else 'user_disabled' end;
        perform unsecure.notify_permission_change(
            _event, null, 'user', NEW.user_id, null);
    end if;

    if OLD.is_locked is distinct from NEW.is_locked then
        _event := case when NEW.is_locked then 'user_locked' else 'user_unlocked' end;
        perform unsecure.notify_permission_change(
            _event, null, 'user', NEW.user_id, null);
    end if;

    return NEW;
end;
$$;

-- Notify on owner changes (INSERT/DELETE)
create or replace function triggers.notify_owner() returns trigger
    language plpgsql
as
$$
declare
    _row   auth.owner;
    _event text;
    _scope text;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'owner_created' else 'owner_deleted' end;
    _scope := case when _row.user_group_id is not null then 'group' else 'tenant' end;

    perform unsecure.notify_permission_change(
        _event, _row.tenant_id, 'user', _row.user_id,
        jsonb_build_object('scope', _scope, 'user_group_id', _row.user_group_id));

    return _row;
end;
$$;

-- Notify on provider changes (UPDATE for disable, DELETE)
create or replace function triggers.notify_provider() returns trigger
    language plpgsql
as
$$
begin
    if TG_OP = 'DELETE' then
        perform unsecure.notify_permission_change(
            'provider_deleted', null, 'provider', null,
            jsonb_build_object('provider_code', OLD.code));
        return OLD;
    end if;

    if OLD.is_active is distinct from NEW.is_active then
        perform unsecure.notify_permission_change(
            case when NEW.is_active then 'provider_enabled' else 'provider_disabled' end,
            null, 'provider', null,
            jsonb_build_object('provider_code', NEW.code));
    end if;

    return NEW;
end;
$$;

-- Notify on perm_set changes (UPDATE — title, is_assignable)
create or replace function triggers.notify_perm_set() returns trigger
    language plpgsql
as
$$
begin
    if OLD.is_assignable is distinct from NEW.is_assignable
        or OLD.title is distinct from NEW.title then
        perform unsecure.notify_permission_change(
            'perm_set_updated', NEW.tenant_id, 'perm_set', NEW.perm_set_id,
            jsonb_build_object('is_assignable', NEW.is_assignable));
    end if;

    return NEW;
end;
$$;

-- Notify on permission assignability changes (UPDATE)
create or replace function triggers.notify_permission() returns trigger
    language plpgsql
as
$$
begin
    if OLD.is_assignable is distinct from NEW.is_assignable then
        perform unsecure.notify_permission_change(
            'permission_assignability_changed', null, 'system', NEW.permission_id,
            jsonb_build_object('full_code', NEW.full_code::text, 'is_assignable', NEW.is_assignable));
    end if;

    return NEW;
end;
$$;

-- Notify BEFORE tenant DELETE
create or replace function triggers.notify_tenant() returns trigger
    language plpgsql
as
$$
begin
    perform unsecure.notify_permission_change(
        'tenant_deleted', OLD.tenant_id, 'tenant', OLD.tenant_id, null);
    return OLD;
end;
$$;

-- Notify on api_key changes (INSERT/DELETE)
create or replace function triggers.notify_api_key() returns trigger
    language plpgsql
as
$$
declare
    _row   auth.api_key;
    _event text;
begin
    _row := coalesce(NEW, OLD);
    _event := case TG_OP when 'INSERT' then 'api_key_created' else 'api_key_deleted' end;

    perform unsecure.notify_permission_change(
        _event, _row.tenant_id, 'api_key', _row.api_key_id,
        jsonb_build_object('api_key', _row.api_key));

    return _row;
end;
$$;


-- =============================================================================
-- PART 3: CREATE TRIGGER STATEMENTS
-- =============================================================================

-- ---- permission_assignment ----
create trigger trg_notify_permission_assignment
    after insert or delete
    on auth.permission_assignment
    for each row
execute function triggers.notify_permission_assignment();

-- ---- perm_set_perm ----
create trigger trg_notify_perm_set_perm
    after insert or delete
    on auth.perm_set_perm
    for each row
execute function triggers.notify_perm_set_perm();

-- ---- user_group_member ----
-- Cache invalidation on delete (covers auth.delete_user_group_member, set_as_external/internal, cascades)
create trigger trg_cache_user_group_member_delete
    after delete
    on auth.user_group_member
    for each row
execute function triggers.cache_user_group_member_delete();

-- Notification on insert/delete
create trigger trg_notify_user_group_member
    after insert or delete
    on auth.user_group_member
    for each row
execute function triggers.notify_user_group_member();

-- ---- user_group ----
-- Cache invalidation on is_active change
create trigger trg_cache_user_group_status
    after update
    on auth.user_group
    for each row
execute function triggers.cache_user_group_status_change();

-- Cache invalidation BEFORE delete (must read members before cascade)
create trigger trg_cache_user_group_before_delete
    before delete
    on auth.user_group
    for each row
execute function triggers.cache_user_group_before_delete();

-- Notification on update/delete
create trigger trg_notify_user_group
    after update or delete
    on auth.user_group
    for each row
execute function triggers.notify_user_group();

-- ---- user_group_mapping ----
create trigger trg_notify_user_group_mapping
    after insert or delete
    on auth.user_group_mapping
    for each row
execute function triggers.notify_user_group_mapping();

-- ---- user_info ----
create trigger trg_notify_user_status
    after update or delete
    on auth.user_info
    for each row
execute function triggers.notify_user_status();

-- ---- owner ----
create trigger trg_notify_owner
    after insert or delete
    on auth.owner
    for each row
execute function triggers.notify_owner();

-- ---- provider ----
-- Cache invalidation BEFORE delete
create trigger trg_cache_provider_before_delete
    before delete
    on auth.provider
    for each row
execute function triggers.cache_provider_before_delete();

-- Cache invalidation + notification on status change
create trigger trg_cache_provider_status
    after update
    on auth.provider
    for each row
execute function triggers.cache_provider_status_change();

create trigger trg_notify_provider
    after update or delete
    on auth.provider
    for each row
execute function triggers.notify_provider();

-- ---- perm_set ----
create trigger trg_notify_perm_set
    after update
    on auth.perm_set
    for each row
execute function triggers.notify_perm_set();

-- ---- permission ----
create trigger trg_notify_permission
    after update
    on auth.permission
    for each row
execute function triggers.notify_permission();

-- ---- tenant ----
create trigger trg_notify_tenant
    before delete
    on auth.tenant
    for each row
execute function triggers.notify_tenant();

-- ---- api_key ----
create trigger trg_notify_api_key
    after insert or delete
    on auth.api_key
    for each row
execute function triggers.notify_api_key();
