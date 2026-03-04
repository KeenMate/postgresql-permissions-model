/*
 * MFA Policy & Reset MFA — Functions
 * ====================================
 *
 * - auth.reset_mfa()           — regenerate recovery codes for confirmed enrollment
 * - auth.create_mfa_policy()   — create an MFA enforcement rule
 * - auth.delete_mfa_policy()   — delete an MFA enforcement rule
 * - auth.get_mfa_policies()    — list MFA policy rules (filtered by scope)
 * - unsecure.is_mfa_required() — resolve whether MFA is required (no permission check)
 * - auth.is_mfa_required()     — permission-checked wrapper
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ---------------------------------------------------------------------------
-- auth.reset_mfa
-- ---------------------------------------------------------------------------
-- Regenerates 10 recovery codes for a confirmed MFA enrollment.
-- Returns new plaintext codes (shown once, stored as SHA-256 hashes).
-- Reuses existing errors: 38002 (not enrolled), 38003 (not confirmed).
-- ---------------------------------------------------------------------------
create or replace function auth.reset_mfa(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _mfa_type_code   text,
    _request_context jsonb default null
) returns table (
    __user_mfa_id    bigint,
    __recovery_codes text[]
)
    language plpgsql
as
$$
declare
    __mfa_record     auth.user_mfa;
    __plain_codes    text[];
    __hashed_codes   text[];
    __code           text;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.reset_mfa');

    -- Verify enrollment exists
    select um.*
    from auth.user_mfa um
    where um.user_id = _target_user_id
      and um.mfa_type_code = _mfa_type_code
    into __mfa_record;

    if __mfa_record.user_mfa_id is null then
        perform error.raise_38002(_target_user_id, _mfa_type_code);
    end if;

    -- Must be confirmed
    if not __mfa_record.is_confirmed then
        perform error.raise_38003(_target_user_id, _mfa_type_code);
    end if;

    -- Generate 10 new recovery codes
    __plain_codes  := array[]::text[];
    __hashed_codes := array[]::text[];
    for _i in 1..10 loop
        __code := helpers.random_string(20);
        __plain_codes  := array_append(__plain_codes, __code);
        __hashed_codes := array_append(__hashed_codes, encode(ext.digest(__code, 'sha256'), 'hex'));
    end loop;

    -- Replace recovery codes
    update auth.user_mfa
    set recovery_codes = __hashed_codes,
        updated_at     = now(),
        updated_by     = _updated_by
    where user_mfa_id = __mfa_record.user_mfa_id;

    -- Log event
    perform unsecure.create_user_event(
        _updated_by, _user_id, _correlation_id, 'mfa_recovery_reset',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object('mfa_type', _mfa_type_code, 'user_mfa_id', __mfa_record.user_mfa_id)
    );

    return query
        select __mfa_record.user_mfa_id, __plain_codes;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.create_mfa_policy
-- ---------------------------------------------------------------------------
-- Creates an MFA enforcement rule. Scope determined by which params are null:
--   all null = global, tenant_id only = tenant-level, etc.
-- ---------------------------------------------------------------------------
create or replace function auth.create_mfa_policy(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer      default null,
    _user_group_id   integer      default null,
    _target_user_id  bigint       default null,
    _mfa_required    boolean      default true,
    _request_context jsonb        default null
) returns table (
    __mfa_policy_id bigint
)
    language plpgsql
as
$$
declare
    __last_item auth.mfa_policy;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.mfa_policy.create_mfa_policy');

    insert into auth.mfa_policy (created_by, updated_by, tenant_id, user_group_id, user_id, mfa_required)
    values (_created_by, _created_by, _tenant_id, _user_group_id, _target_user_id, _mfa_required)
    returning *
        into __last_item;

    -- Log event
    perform unsecure.create_user_event(
        _created_by, _user_id, _correlation_id, 'mfa_policy_created',
        _target_user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object(
            'mfa_policy_id', __last_item.mfa_policy_id,
            'tenant_id', _tenant_id,
            'user_group_id', _user_group_id,
            'target_user_id', _target_user_id,
            'mfa_required', _mfa_required
        )
    );

    return query
        select __last_item.mfa_policy_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.delete_mfa_policy
-- ---------------------------------------------------------------------------
create or replace function auth.delete_mfa_policy(
    _deleted_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _mfa_policy_id   bigint,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
declare
    __existing auth.mfa_policy;
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.mfa_policy.delete_mfa_policy');

    -- Validate policy exists
    select mp.*
    from auth.mfa_policy mp
    where mp.mfa_policy_id = _mfa_policy_id
    into __existing;

    if __existing.mfa_policy_id is null then
        perform error.raise_38007(_mfa_policy_id);
    end if;

    -- Delete
    delete from auth.mfa_policy
    where mfa_policy_id = _mfa_policy_id;

    -- Log event
    perform unsecure.create_user_event(
        _deleted_by, _user_id, _correlation_id, 'mfa_policy_deleted',
        __existing.user_id,
        _request_context := _request_context,
        _event_data := jsonb_build_object(
            'mfa_policy_id', _mfa_policy_id,
            'tenant_id', __existing.tenant_id,
            'user_group_id', __existing.user_group_id,
            'user_id', __existing.user_id,
            'mfa_required', __existing.mfa_required
        )
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.get_mfa_policies
-- ---------------------------------------------------------------------------
-- Returns MFA policy rules, optionally filtered by scope params.
-- All params null = return all policies.
-- ---------------------------------------------------------------------------
create or replace function auth.get_mfa_policies(
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer default null,
    _user_group_id   integer default null,
    _target_user_id  bigint  default null
) returns table (
    __mfa_policy_id  bigint,
    __tenant_id      integer,
    __user_group_id  integer,
    __user_id        bigint,
    __mfa_required   boolean,
    __created_at     timestamp with time zone,
    __created_by     text
)
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.mfa_policy.get_mfa_policies');

    return query
        select mp.mfa_policy_id,
               mp.tenant_id,
               mp.user_group_id,
               mp.user_id,
               mp.mfa_required,
               mp.created_at,
               mp.created_by
        from auth.mfa_policy mp
        where (_tenant_id is null or mp.tenant_id = _tenant_id)
          and (_user_group_id is null or mp.user_group_id = _user_group_id)
          and (_target_user_id is null or mp.user_id = _target_user_id)
        order by mp.mfa_policy_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- unsecure.is_mfa_required
-- ---------------------------------------------------------------------------
-- Resolves whether MFA is required for a user in a tenant context.
-- No permission check — called during login flows from trusted context.
--
-- Resolution order (most specific wins):
--   1. User-level (tenant-specific user > global user)
--   2. Group-level (bool_or across matching group policies)
--   3. Tenant-level
--   4. Global (all nulls)
--   5. No match → false
-- ---------------------------------------------------------------------------
create or replace function unsecure.is_mfa_required(
    _target_user_id bigint,
    _tenant_id      integer default 1
) returns boolean
    language plpgsql
as
$$
declare
    __result    boolean;
    __group_ids integer[];
begin
    -- 1. User-level: tenant-specific user rule wins over global user rule
    select mp.mfa_required
    from auth.mfa_policy mp
    where mp.user_id = _target_user_id
      and mp.user_group_id is null
      and (mp.tenant_id = _tenant_id or mp.tenant_id is null)
    order by mp.tenant_id nulls last  -- tenant-specific wins over global
    limit 1
    into __result;

    if __result is not null then
        return __result;
    end if;

    -- 2. Group-level: uses cached group IDs for consistency
    __group_ids := unsecure.get_cached_group_ids(_target_user_id, _tenant_id);

    if __group_ids is not null and array_length(__group_ids, 1) > 0 then
        select bool_or(mp.mfa_required)
        from auth.mfa_policy mp
        where mp.user_group_id = any(__group_ids)
          and mp.user_id is null
          and (mp.tenant_id = _tenant_id or mp.tenant_id is null)
        into __result;

        if __result is not null then
            return __result;
        end if;
    end if;

    -- 3. Tenant-level
    select mp.mfa_required
    from auth.mfa_policy mp
    where mp.tenant_id = _tenant_id
      and mp.user_group_id is null
      and mp.user_id is null
    into __result;

    if __result is not null then
        return __result;
    end if;

    -- 4. Global (all nulls)
    select mp.mfa_required
    from auth.mfa_policy mp
    where mp.tenant_id is null
      and mp.user_group_id is null
      and mp.user_id is null
    into __result;

    if __result is not null then
        return __result;
    end if;

    -- 5. No match → false
    return false;
end;
$$;

-- ---------------------------------------------------------------------------
-- auth.is_mfa_required
-- ---------------------------------------------------------------------------
-- Permission-checked wrapper around unsecure.is_mfa_required.
-- Reuses mfa.get_mfa_status permission.
-- ---------------------------------------------------------------------------
create or replace function auth.is_mfa_required(
    _user_id         bigint,
    _correlation_id  text,
    _target_user_id  bigint,
    _tenant_id       integer default 1
) returns boolean
    language plpgsql
as
$$
begin
    perform
        auth.has_permission(_user_id, _correlation_id, 'mfa.get_mfa_status');

    return unsecure.is_mfa_required(_target_user_id, _tenant_id);
end;
$$;
