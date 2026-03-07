/*
 * Invitation System — Functions
 * ==============================
 *
 * unsecure layer:
 *   1. unsecure.create_invitation
 *   2. unsecure.accept_invitation
 *   3. unsecure.reject_invitation
 *   4. unsecure.revoke_invitation
 *   5. unsecure.complete_invitation_action
 *   6. unsecure.fail_invitation_action
 *   7. unsecure.check_invitation_completion
 *   8. unsecure.evaluate_invitation_condition
 *   9. unsecure.get_invitations
 *  10. unsecure.get_invitation_actions
 *  11. unsecure.create_invitation_from_template
 *  12. unsecure.execute_database_action
 *  13. unsecure.process_invitation_actions
 *
 * auth layer:
 *  14. auth.create_invitation
 *  15. auth.accept_invitation
 *  16. auth.reject_invitation
 *  17. auth.revoke_invitation
 *  18. auth.get_invitations
 *  19. auth.get_invitation_actions
 *  20. auth.create_invitation_from_template
 *
 * Template management:
 *  21. unsecure.create_invitation_template
 *  22. unsecure.update_invitation_template
 *  23. unsecure.delete_invitation_template
 *  24. auth.create_invitation_template
 *  25. auth.update_invitation_template
 *  26. auth.delete_invitation_template
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ===========================================================================
-- 1. unsecure.create_invitation
-- ===========================================================================
create or replace function unsecure.create_invitation(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer,
    _target_email    text,
    _message         text default null,
    _expires_at      timestamptz default null,
    _extra_data      jsonb default null
) returns table(__invitation_id bigint, __uuid uuid)
    language plpgsql
as
$$
declare
    ___invitation_id bigint;
    ___uuid uuid;
    ___default_expiry interval := interval '7 days';
begin
    insert into auth.invitation (created_by, updated_by, tenant_id, inviter_user_id, target_email, message, expires_at, extra_data)
    values (_created_by, _created_by, _tenant_id, _user_id, _target_email, _message,
            coalesce(_expires_at, now() + ___default_expiry), _extra_data)
    returning invitation.invitation_id, invitation.uuid
        into ___invitation_id, ___uuid;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id,
        22001, 'invitation', ___invitation_id,
        jsonb_build_object('target_email', _target_email, 'tenant_id', _tenant_id),
        _tenant_id);

    return query select ___invitation_id, ___uuid;
end;
$$;

-- ===========================================================================
-- 2. unsecure.accept_invitation
-- ===========================================================================
create or replace function unsecure.accept_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint,
    _target_user_id  bigint
) returns void
    language plpgsql
as
$$
declare
    ___inv record;
begin
    select invitation_id, status_code, expires_at, tenant_id, target_email
    from auth.invitation
    where invitation_id = _invitation_id
    into ___inv;

    if ___inv is null then
        perform error.raise_39001(_invitation_id);
    end if;

    if ___inv.status_code <> 'pending' then
        perform error.raise_39002(_invitation_id, ___inv.status_code);
    end if;

    if ___inv.expires_at < now() then
        update auth.invitation
        set status_code = 'expired', updated_by = _updated_by, updated_at = now()
        where invitation_id = _invitation_id;
        perform error.raise_39003(_invitation_id);
    end if;

    update auth.invitation
    set status_code = 'processing',
        target_user_id = _target_user_id,
        accepted_at = now(),
        updated_by = _updated_by,
        updated_at = now()
    where invitation_id = _invitation_id;

    -- Skip actions from non-accept phases (on_reject, on_expired)
    update auth.invitation_action
    set status_code = 'skipped', updated_by = _updated_by, updated_at = now()
    where invitation_id = _invitation_id
      and status_code = 'pending'
      and phase_code not in ('on_accept', 'on_create');

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22002, 'invitation', _invitation_id,
        jsonb_build_object('target_email', ___inv.target_email, 'tenant_id', ___inv.tenant_id),
        ___inv.tenant_id);
end;
$$;

-- ===========================================================================
-- 3. unsecure.reject_invitation
-- ===========================================================================
create or replace function unsecure.reject_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint
) returns void
    language plpgsql
as
$$
declare
    ___inv record;
begin
    select invitation_id, status_code, expires_at, tenant_id, target_email
    from auth.invitation
    where invitation_id = _invitation_id
    into ___inv;

    if ___inv is null then
        perform error.raise_39001(_invitation_id);
    end if;

    if ___inv.status_code <> 'pending' then
        perform error.raise_39002(_invitation_id, ___inv.status_code);
    end if;

    update auth.invitation
    set status_code = 'rejected',
        rejected_at = now(),
        updated_by = _updated_by,
        updated_at = now()
    where invitation_id = _invitation_id;

    -- Skip all non-reject-phase actions
    update auth.invitation_action
    set status_code = 'skipped', updated_by = _updated_by, updated_at = now()
    where invitation_id = _invitation_id
      and status_code = 'pending'
      and phase_code <> 'on_reject';

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22003, 'invitation', _invitation_id,
        jsonb_build_object('target_email', ___inv.target_email, 'tenant_id', ___inv.tenant_id),
        ___inv.tenant_id);
end;
$$;

-- ===========================================================================
-- 4. unsecure.revoke_invitation
-- ===========================================================================
create or replace function unsecure.revoke_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint
) returns void
    language plpgsql
as
$$
declare
    ___inv record;
begin
    select invitation_id, status_code, tenant_id, target_email
    from auth.invitation
    where invitation_id = _invitation_id
    into ___inv;

    if ___inv is null then
        perform error.raise_39001(_invitation_id);
    end if;

    if ___inv.status_code <> 'pending' then
        perform error.raise_39002(_invitation_id, ___inv.status_code);
    end if;

    update auth.invitation
    set status_code = 'revoked',
        revoked_at = now(),
        updated_by = _updated_by,
        updated_at = now()
    where invitation_id = _invitation_id;

    -- Skip all pending actions
    update auth.invitation_action
    set status_code = 'skipped', updated_by = _updated_by, updated_at = now()
    where invitation_id = _invitation_id and status_code = 'pending';

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22004, 'invitation', _invitation_id,
        jsonb_build_object('target_email', ___inv.target_email, 'tenant_id', ___inv.tenant_id),
        ___inv.tenant_id);
end;
$$;

-- ===========================================================================
-- 5. unsecure.complete_invitation_action
-- ===========================================================================
create or replace function unsecure.complete_invitation_action(
    _updated_by            text,
    _user_id               bigint,
    _correlation_id        text,
    _invitation_action_id  bigint,
    _result_data           jsonb default null
) returns void
    language plpgsql
as
$$
declare
    ___action record;
begin
    select ia.invitation_action_id, ia.status_code, ia.invitation_id, ia.action_type_code,
           inv.target_email, inv.tenant_id
    from auth.invitation_action ia
    inner join auth.invitation inv on inv.invitation_id = ia.invitation_id
    where ia.invitation_action_id = _invitation_action_id
    into ___action;

    if ___action is null then
        perform error.raise_39004(_invitation_action_id);
    end if;

    if ___action.status_code not in ('pending', 'processing') then
        perform error.raise_39005(_invitation_action_id);
    end if;

    update auth.invitation_action
    set status_code = 'completed',
        result_data = _result_data,
        completed_at = now(),
        updated_by = _updated_by,
        updated_at = now()
    where invitation_action_id = _invitation_action_id;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22006, 'invitation', ___action.invitation_id,
        jsonb_build_object('action_type', ___action.action_type_code, 'target_email', ___action.target_email),
        ___action.tenant_id);

    -- Check if all actions are done for this invitation
    perform unsecure.check_invitation_completion(_updated_by, _user_id, _correlation_id, ___action.invitation_id);
end;
$$;

-- ===========================================================================
-- 6. unsecure.fail_invitation_action
-- ===========================================================================
create or replace function unsecure.fail_invitation_action(
    _updated_by            text,
    _user_id               bigint,
    _correlation_id        text,
    _invitation_action_id  bigint,
    _error_message         text default null
) returns void
    language plpgsql
as
$$
declare
    ___action record;
begin
    select ia.invitation_action_id, ia.status_code, ia.invitation_id, ia.action_type_code,
           ia.is_required, ia.sequence, ia.phase_code,
           inv.target_email, inv.tenant_id
    from auth.invitation_action ia
    inner join auth.invitation inv on inv.invitation_id = ia.invitation_id
    where ia.invitation_action_id = _invitation_action_id
    into ___action;

    if ___action is null then
        perform error.raise_39004(_invitation_action_id);
    end if;

    if ___action.status_code not in ('pending', 'processing') then
        perform error.raise_39005(_invitation_action_id);
    end if;

    update auth.invitation_action
    set status_code = 'failed',
        error_message = _error_message,
        completed_at = now(),
        updated_by = _updated_by,
        updated_at = now()
    where invitation_action_id = _invitation_action_id;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22007, 'invitation', ___action.invitation_id,
        jsonb_build_object('action_type', ___action.action_type_code, 'target_email', ___action.target_email,
                           'error_message', coalesce(_error_message, 'unknown')),
        ___action.tenant_id);

    -- If this was a required action, skip remaining actions in later sequences (same phase) and fail the invitation
    if ___action.is_required then
        update auth.invitation_action
        set status_code = 'skipped', updated_by = _updated_by, updated_at = now()
        where invitation_id = ___action.invitation_id
          and phase_code = ___action.phase_code
          and sequence > ___action.sequence
          and status_code = 'pending';

        update auth.invitation
        set status_code = 'failed', updated_by = _updated_by, updated_at = now()
        where invitation_id = ___action.invitation_id;

        perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
            22009, 'invitation', ___action.invitation_id,
            jsonb_build_object('action_type', ___action.action_type_code, 'target_email', ___action.target_email),
            ___action.tenant_id);
    else
        -- Non-required action failed — check if invitation can still complete
        perform unsecure.check_invitation_completion(_updated_by, _user_id, _correlation_id, ___action.invitation_id);
    end if;
end;
$$;

-- ===========================================================================
-- 7. Helper: check if all actions are done and mark invitation completed
-- ===========================================================================
create or replace function unsecure.check_invitation_completion(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint
) returns void
    language plpgsql
as
$$
declare
    ___pending_count integer;
    ___inv record;
begin
    select count(*)
    from auth.invitation_action
    where invitation_id = _invitation_id
      and status_code in ('pending', 'processing')
    into ___pending_count;

    if ___pending_count = 0 then
        select target_email, tenant_id from auth.invitation where invitation_id = _invitation_id into ___inv;

        update auth.invitation
        set status_code = 'completed', updated_by = _updated_by, updated_at = now()
        where invitation_id = _invitation_id
          and status_code in ('processing', 'accepted');

        perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
            22008, 'invitation', _invitation_id,
            jsonb_build_object('target_email', ___inv.target_email),
            ___inv.tenant_id);
    end if;
end;
$$;

-- ===========================================================================
-- 8. unsecure.evaluate_invitation_condition
--
-- Evaluates a condition_code against current state.
-- Returns true if the action should execute, false to skip.
-- ===========================================================================
create or replace function unsecure.evaluate_invitation_condition(
    _condition_code  text,
    _target_user_id  bigint,
    _tenant_id       integer,
    _payload         jsonb
) returns boolean
    language plpgsql
as
$$
declare
    ___group_id integer;
    ___perm_set_code text;
    ___resource_type text;
    ___resource_id bigint;
begin
    case _condition_code
        when 'always' then
            return true;

        when 'user_not_in_tenant' then
            if _target_user_id is null then
                return true;  -- user doesn't exist yet, condition met
            end if;
            return not exists(
                select 1 from auth.tenant_user
                where tenant_id = _tenant_id and user_id = _target_user_id
            );

        when 'user_not_in_group' then
            if _target_user_id is null then
                return true;
            end if;
            ___group_id := (_payload->>'user_group_id')::integer;
            return not exists(
                select 1 from auth.user_group_member
                where user_group_id = ___group_id and user_id = _target_user_id
            );

        when 'user_has_no_perm_set' then
            if _target_user_id is null then
                return true;
            end if;
            ___perm_set_code := _payload->>'perm_set_code';
            return not exists(
                select 1 from auth.permission_assignment pa
                inner join auth.perm_set ps on ps.perm_set_id = pa.perm_set_id
                where pa.user_id = _target_user_id
                  and pa.tenant_id = _tenant_id
                  and ps.code = ___perm_set_code
            );

        when 'user_has_no_resource_access' then
            if _target_user_id is null then
                return true;
            end if;
            ___resource_type := _payload->>'resource_type';
            ___resource_id := (_payload->>'resource_id')::bigint;
            return not exists(
                select 1 from auth.resource_access
                where tenant_id = _tenant_id
                  and resource_type = ___resource_type
                  and resource_id = ___resource_id
                  and user_id = _target_user_id
                  and not is_deny
            );

        else
            -- Unknown condition — default to execute
            return true;
    end case;
end;
$$;

-- ===========================================================================
-- 8b. unsecure.resolve_action_payload
--
-- Builds the final payload for a backend/external action by resolving
-- the action type's payload_schema against invitation context + action payload.
-- Fields with "source": "invitation.<col>" are auto-populated.
-- Fields with "source": null must already exist in the action payload.
-- Action payload values always win over auto-populated ones.
-- ===========================================================================
create or replace function unsecure.resolve_action_payload(
    _action_type_code text,
    _action_payload   jsonb,
    _invitation_context jsonb
) returns jsonb
    language plpgsql
as
$$
declare
    ___schema jsonb;
    ___fields jsonb;
    ___resolved jsonb := '{}'::jsonb;
    ___field_name text;
    ___field_def jsonb;
    ___source text;
    ___source_key text;
    ___value jsonb;
begin
    -- Load schema
    select payload_schema from const.invitation_action_type where code = _action_type_code into ___schema;
    ___fields := ___schema->'fields';

    if ___fields is null or ___fields = '{}'::jsonb then
        -- No schema — return action payload as-is
        return _action_payload;
    end if;

    -- Resolve each field from schema
    for ___field_name, ___field_def in select * from jsonb_each(___fields)
    loop
        -- Action payload always takes precedence
        if _action_payload ? ___field_name then
            ___resolved := ___resolved || jsonb_build_object(___field_name, _action_payload->___field_name);
            continue;
        end if;

        -- Try auto-populate from source
        ___source := ___field_def->>'source';
        if ___source is not null and ___source like 'invitation.%' then
            ___source_key := substring(___source from 12);  -- strip 'invitation.'
            ___value := _invitation_context->___source_key;
            if ___value is not null and ___value != 'null'::jsonb then
                ___resolved := ___resolved || jsonb_build_object(___field_name, ___value);
            end if;
        end if;
    end loop;

    -- Start with action payload (custom fields), then overlay resolved schema fields
    return _action_payload || ___resolved;
end;
$$;

-- ===========================================================================
-- 9. unsecure.get_invitations
-- ===========================================================================
create or replace function unsecure.get_invitations(
    _requested_by    text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer default 1,
    _status_code     text default null,
    _target_email    text default null,
    _inviter_user_id bigint default null
) returns table(
    __invitation_id   bigint,
    __uuid            uuid,
    __tenant_id       integer,
    __inviter_user_id bigint,
    __target_email    text,
    __target_user_id  bigint,
    __status_code     text,
    __message         text,
    __template_code   text,
    __expires_at      timestamptz,
    __accepted_at     timestamptz,
    __rejected_at     timestamptz,
    __revoked_at      timestamptz,
    __created_at      timestamptz,
    __created_by      text,
    __action_count    bigint,
    __pending_actions  bigint
)
    language plpgsql
as
$$
begin
    return query
        select i.invitation_id, i.uuid, i.tenant_id, i.inviter_user_id,
               i.target_email, i.target_user_id, i.status_code, i.message,
               i.template_code, i.expires_at, i.accepted_at, i.rejected_at, i.revoked_at,
               i.created_at, i.created_by,
               count(ia.invitation_action_id),
               count(ia.invitation_action_id) filter (where ia.status_code in ('pending', 'processing'))
        from auth.invitation i
        left join auth.invitation_action ia on ia.invitation_id = i.invitation_id
        where i.tenant_id = _tenant_id
          and (_status_code is null or i.status_code = _status_code)
          and (_target_email is null or i.target_email ilike '%' || _target_email || '%')
          and (_inviter_user_id is null or i.inviter_user_id = _inviter_user_id)
        group by i.invitation_id
        order by i.created_at desc;
end;
$$;

-- ===========================================================================
-- 10. unsecure.get_invitation_actions
-- ===========================================================================
create or replace function unsecure.get_invitation_actions(
    _requested_by    text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint
) returns table(
    __invitation_action_id bigint,
    __action_type_code     text,
    __executor_code        text,
    __phase_code           text,
    __condition_code       text,
    __sequence             integer,
    __is_required          boolean,
    __status_code          text,
    __payload              jsonb,
    __result_data          jsonb,
    __error_message        text,
    __completed_at         timestamptz,
    __created_at           timestamptz
)
    language plpgsql
as
$$
begin
    return query
        select ia.invitation_action_id, ia.action_type_code, ia.executor_code,
               ia.phase_code, ia.condition_code,
               ia.sequence, ia.is_required, ia.status_code,
               ia.payload, ia.result_data, ia.error_message, ia.completed_at, ia.created_at
        from auth.invitation_action ia
        where ia.invitation_id = _invitation_id
        order by ia.phase_code, ia.sequence, ia.invitation_action_id;
end;
$$;

-- ===========================================================================
-- 11. unsecure.create_invitation_from_template
-- ===========================================================================
create or replace function unsecure.create_invitation_from_template(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer,
    _template_code   text,
    _target_email    text,
    _message         text default null,
    _expires_at      timestamptz default null,
    _payload_overrides jsonb default null,
    _extra_data      jsonb default null
) returns table(__invitation_id bigint, __uuid uuid)
    language plpgsql
as
$$
declare
    ___tmpl record;
    ___invitation_id bigint;
    ___uuid uuid;
    ___tmpl_action record;
    ___merged_payload jsonb;
begin
    -- Find template (tenant-specific takes precedence over global)
    select template_id, code, default_message, tenant_id
    from auth.invitation_template
    where code = _template_code
      and (tenant_id = _tenant_id or tenant_id is null)
      and is_active = true
    order by tenant_id nulls last
    limit 1
    into ___tmpl;

    if ___tmpl is null then
        perform error.raise_39006(_template_code);
    end if;

    -- Create invitation
    select * from unsecure.create_invitation(
        _created_by, _user_id, _correlation_id, _tenant_id, _target_email,
        coalesce(_message, ___tmpl.default_message), _expires_at, _extra_data
    ) into ___invitation_id, ___uuid;

    -- Store template reference
    update auth.invitation
    set template_code = _template_code
    where invitation_id = ___invitation_id;

    -- Create actions from template
    for ___tmpl_action in
        select action_type_code, executor_code, phase_code, condition_code,
               sequence, is_required, payload_template
        from auth.invitation_template_action
        where template_id = ___tmpl.template_id
        order by sequence, template_action_id
    loop
        -- Merge payload: template defaults overridden by caller
        ___merged_payload := ___tmpl_action.payload_template;
        if _payload_overrides is not null then
            ___merged_payload := ___merged_payload || _payload_overrides;
        end if;

        insert into auth.invitation_action (
            created_by, updated_by, invitation_id, action_type_code, executor_code,
            phase_code, condition_code, sequence, is_required, payload
        ) values (
            _created_by, _created_by, ___invitation_id, ___tmpl_action.action_type_code,
            ___tmpl_action.executor_code, ___tmpl_action.phase_code, ___tmpl_action.condition_code,
            ___tmpl_action.sequence, ___tmpl_action.is_required,
            ___merged_payload
        );
    end loop;

    return query select ___invitation_id, ___uuid;
end;
$$;

-- ===========================================================================
-- 12. unsecure.execute_database_action — execute a single database action
-- ===========================================================================
create or replace function unsecure.execute_database_action(
    _updated_by            text,
    _user_id               bigint,
    _correlation_id        text,
    _invitation_action_id  bigint,
    _invitation_id         bigint,
    _target_user_id        bigint,
    _action_type_code      text,
    _payload               jsonb,
    _tenant_id             integer
) returns void
    language plpgsql
as
$$
declare
    ___group_id integer;
    ___perm_set_code text;
    ___perm_code text;
    ___resource_type text;
    ___resource_id bigint;
    ___access_flags text[];
begin
    case _action_type_code
        when 'add_tenant_user' then
            insert into auth.tenant_user (created_by, tenant_id, user_id)
            values (_updated_by, _tenant_id, _target_user_id)
            on conflict (tenant_id, user_id) do nothing;

        when 'add_group_member' then
            ___group_id := (_payload->>'user_group_id')::integer;
            perform unsecure.create_user_group_member(
                _updated_by, _user_id, _correlation_id,
                ___group_id, _target_user_id, _tenant_id
            );

        when 'assign_perm_set' then
            ___perm_set_code := _payload->>'perm_set_code';
            perform unsecure.assign_permission(
                _updated_by, _user_id, _correlation_id,
                null, _target_user_id, ___perm_set_code, null, _tenant_id
            );

        when 'assign_permission' then
            ___perm_code := _payload->>'permission_code';
            perform unsecure.assign_permission(
                _updated_by, _user_id, _correlation_id,
                null, _target_user_id, null, ___perm_code, _tenant_id
            );

        when 'grant_resource_access' then
            ___resource_type := _payload->>'resource_type';
            ___resource_id := (_payload->>'resource_id')::bigint;
            ___access_flags := array(select jsonb_array_elements_text(_payload->'access_flags'));
            if ___access_flags is null or array_length(___access_flags, 1) is null then
                ___access_flags := array['read'];
            end if;
            perform auth.grant_resource_access(
                _updated_by, _user_id, _correlation_id,
                ___resource_type, ___resource_id,
                _target_user_id, null, ___access_flags, _tenant_id
            );

        else
            -- Unknown database action type — treat as no-op
            null;
    end case;
end;
$$;

-- ===========================================================================
-- 13. unsecure.process_invitation_actions
--
-- Processes actions for a given phase. Database actions execute immediately.
-- Backend/external actions are returned as pending for the caller to handle.
-- Conditions are evaluated before each action; false => skipped.
-- ===========================================================================
create or replace function unsecure.process_invitation_actions(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint,
    _phase_code      text default 'on_accept'
) returns table(
    __invitation_action_id bigint,
    __action_type_code     text,
    __executor_code        text,
    __sequence             integer,
    __payload              jsonb
)
    language plpgsql
as
$$
declare
    ___inv record;
    ___action record;
    ___current_seq integer := -1;
    ___seq_failed boolean := false;
    ___condition_met boolean;
    ___enriched_payload jsonb;
begin
    select i.invitation_id, i.tenant_id, i.target_user_id, i.target_email,
           i.uuid, i.inviter_user_id, i.message, i.status_code
    from auth.invitation i
    where i.invitation_id = _invitation_id
    into ___inv;

    if ___inv is null then
        perform error.raise_39001(_invitation_id);
    end if;

    -- Process actions in sequence order for the requested phase
    for ___action in
        select ia.invitation_action_id, ia.action_type_code, ia.executor_code,
               ia.sequence, ia.is_required, ia.payload, ia.status_code,
               ia.condition_code
        from auth.invitation_action ia
        where ia.invitation_id = _invitation_id
          and ia.phase_code = _phase_code
          and ia.status_code = 'pending'
        order by ia.sequence, ia.invitation_action_id
    loop
        -- If we moved to a new sequence group and the previous one had a required failure, stop
        if ___action.sequence > ___current_seq and ___seq_failed then
            exit;
        end if;
        ___current_seq := ___action.sequence;

        -- Evaluate condition
        ___condition_met := unsecure.evaluate_invitation_condition(
            ___action.condition_code, ___inv.target_user_id, ___inv.tenant_id, ___action.payload
        );

        if not ___condition_met then
            -- Condition not met — skip this action
            update auth.invitation_action
            set status_code = 'skipped', updated_by = _updated_by, updated_at = now()
            where invitation_action_id = ___action.invitation_action_id;
            continue;
        end if;

        if ___action.executor_code = 'database' then
            -- Execute database actions directly
            begin
                update auth.invitation_action
                set status_code = 'processing', updated_by = _updated_by, updated_at = now()
                where invitation_action_id = ___action.invitation_action_id;

                perform unsecure.execute_database_action(
                    _updated_by, _user_id, _correlation_id,
                    ___action.invitation_action_id, _invitation_id,
                    ___inv.target_user_id, ___action.action_type_code,
                    ___action.payload, ___inv.tenant_id
                );

                perform unsecure.complete_invitation_action(
                    _updated_by, _user_id, _correlation_id,
                    ___action.invitation_action_id
                );
            exception when others then
                perform unsecure.fail_invitation_action(
                    _updated_by, _user_id, _correlation_id,
                    ___action.invitation_action_id,
                    sqlerrm
                );
                if ___action.is_required then
                    ___seq_failed := true;
                end if;
            end;
        else
            -- Backend/external actions: mark as processing and return to caller
            update auth.invitation_action
            set status_code = 'processing', updated_by = _updated_by, updated_at = now()
            where invitation_action_id = ___action.invitation_action_id;

            -- Resolve payload from action type schema + invitation context
            ___enriched_payload := unsecure.resolve_action_payload(
                ___action.action_type_code,
                ___action.payload,
                jsonb_build_object(
                    'invitation_id',    ___inv.invitation_id,
                    'uuid',             ___inv.uuid,
                    'tenant_id',        ___inv.tenant_id,
                    'target_email',     ___inv.target_email,
                    'target_user_id',   ___inv.target_user_id,
                    'inviter_user_id',  ___inv.inviter_user_id,
                    'message',          ___inv.message,
                    'status_code',      ___inv.status_code
                )
            );

            return query select ___action.invitation_action_id, ___action.action_type_code,
                                ___action.executor_code, ___action.sequence, ___enriched_payload;
        end if;
    end loop;

    -- After processing all actions, check if the invitation can be marked completed
    -- (handles cases where all actions were skipped by conditions or already done)
    perform unsecure.check_invitation_completion(
        _updated_by, _user_id, _correlation_id, _invitation_id
    );
end;
$$;

-- ===========================================================================
-- 14. auth.create_invitation
-- ===========================================================================
create or replace function auth.create_invitation(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer,
    _target_email    text,
    _actions         jsonb default '[]'::jsonb,
    _message         text default null,
    _expires_at      timestamptz default null,
    _extra_data      jsonb default null,
    _request_context jsonb default null
) returns table(__invitation_id bigint, __uuid uuid, __on_create_actions jsonb)
    language plpgsql
as
$$
declare
    ___invitation_id bigint;
    ___uuid uuid;
    ___action jsonb;
    ___pending_actions jsonb;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.create_invitation');

    select * from unsecure.create_invitation(
        _created_by, _user_id, _correlation_id, _tenant_id, _target_email,
        _message, _expires_at, _extra_data
    ) into ___invitation_id, ___uuid;

    -- Create actions from the provided JSON array
    for ___action in select * from jsonb_array_elements(_actions)
    loop
        insert into auth.invitation_action (
            created_by, updated_by, invitation_id, action_type_code, executor_code,
            phase_code, condition_code, sequence, is_required, payload
        ) values (
            _created_by, _created_by, ___invitation_id,
            ___action->>'action_type_code',
            coalesce(___action->>'executor_code',
                     (select executor_code from const.invitation_action_type where code = ___action->>'action_type_code')),
            coalesce(___action->>'phase_code', 'on_accept'),
            coalesce(___action->>'condition_code', 'always'),
            coalesce((___action->>'sequence')::integer, 0),
            coalesce((___action->>'is_required')::boolean, true),
            coalesce(___action->'payload', '{}'::jsonb)
        );
    end loop;

    perform unsecure.create_user_event(_created_by, _user_id, _correlation_id,
        'invitation_created', null, _request_context := _request_context,
        _event_data := jsonb_build_object('invitation_id', ___invitation_id, 'target_email', _target_email, 'tenant_id', _tenant_id));

    -- Process on_create phase actions immediately
    select coalesce(jsonb_agg(jsonb_build_object(
        'invitation_action_id', p.__invitation_action_id,
        'action_type_code', p.__action_type_code,
        'executor_code', p.__executor_code,
        'sequence', p.__sequence,
        'payload', p.__payload
    )), '[]'::jsonb)
    from unsecure.process_invitation_actions(
        _created_by, _user_id, _correlation_id, ___invitation_id, 'on_create'
    ) p
    into ___pending_actions;

    return query select ___invitation_id, ___uuid, ___pending_actions;
end;
$$;

-- ===========================================================================
-- 15. auth.accept_invitation
-- ===========================================================================
create or replace function auth.accept_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint,
    _target_user_id  bigint,
    _request_context jsonb default null
) returns table(
    __invitation_action_id bigint,
    __action_type_code     text,
    __executor_code        text,
    __sequence             integer,
    __payload              jsonb
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.accept_invitation');

    perform unsecure.accept_invitation(
        _updated_by, _user_id, _correlation_id, _invitation_id, _target_user_id
    );

    perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
        'invitation_accepted', _target_user_id, _request_context := _request_context,
        _event_data := jsonb_build_object('invitation_id', _invitation_id));

    -- Process on_accept phase actions
    return query select * from unsecure.process_invitation_actions(
        _updated_by, _user_id, _correlation_id, _invitation_id, 'on_accept'
    );
end;
$$;

-- ===========================================================================
-- 16. auth.reject_invitation
-- ===========================================================================
create or replace function auth.reject_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint,
    _request_context jsonb default null
) returns table(
    __invitation_action_id bigint,
    __action_type_code     text,
    __executor_code        text,
    __sequence             integer,
    __payload              jsonb
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.reject_invitation');

    perform unsecure.reject_invitation(
        _updated_by, _user_id, _correlation_id, _invitation_id
    );

    perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
        'invitation_rejected', null, _request_context := _request_context,
        _event_data := jsonb_build_object('invitation_id', _invitation_id));

    -- Process on_reject phase actions (e.g. notify inviter of rejection)
    return query select * from unsecure.process_invitation_actions(
        _updated_by, _user_id, _correlation_id, _invitation_id, 'on_reject'
    );
end;
$$;

-- ===========================================================================
-- 17. auth.revoke_invitation
-- ===========================================================================
create or replace function auth.revoke_invitation(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.revoke_invitation');

    perform unsecure.revoke_invitation(
        _updated_by, _user_id, _correlation_id, _invitation_id
    );

    perform unsecure.create_user_event(_updated_by, _user_id, _correlation_id,
        'invitation_revoked', null, _request_context := _request_context,
        _event_data := jsonb_build_object('invitation_id', _invitation_id));
end;
$$;

-- ===========================================================================
-- 18. auth.get_invitations
-- ===========================================================================
create or replace function auth.get_invitations(
    _requested_by    text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer default 1,
    _status_code     text default null,
    _target_email    text default null,
    _inviter_user_id bigint default null
) returns table(
    __invitation_id   bigint,
    __uuid            uuid,
    __tenant_id       integer,
    __inviter_user_id bigint,
    __target_email    text,
    __target_user_id  bigint,
    __status_code     text,
    __message         text,
    __template_code   text,
    __expires_at      timestamptz,
    __accepted_at     timestamptz,
    __rejected_at     timestamptz,
    __revoked_at      timestamptz,
    __created_at      timestamptz,
    __created_by      text,
    __action_count    bigint,
    __pending_actions  bigint
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.get_invitations');

    return query select * from unsecure.get_invitations(
        _requested_by, _user_id, _correlation_id, _tenant_id,
        _status_code, _target_email, _inviter_user_id
    );
end;
$$;

-- ===========================================================================
-- 19. auth.get_invitation_actions
-- ===========================================================================
create or replace function auth.get_invitation_actions(
    _requested_by    text,
    _user_id         bigint,
    _correlation_id  text,
    _invitation_id   bigint
) returns table(
    __invitation_action_id bigint,
    __action_type_code     text,
    __executor_code        text,
    __phase_code           text,
    __condition_code       text,
    __sequence             integer,
    __is_required          boolean,
    __status_code          text,
    __payload              jsonb,
    __result_data          jsonb,
    __error_message        text,
    __completed_at         timestamptz,
    __created_at           timestamptz
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.get_invitations');

    return query select * from unsecure.get_invitation_actions(
        _requested_by, _user_id, _correlation_id, _invitation_id
    );
end;
$$;

-- ===========================================================================
-- 20. auth.create_invitation_from_template
-- ===========================================================================
create or replace function auth.create_invitation_from_template(
    _created_by        text,
    _user_id           bigint,
    _correlation_id    text,
    _tenant_id         integer,
    _template_code     text,
    _target_email      text,
    _message           text default null,
    _expires_at        timestamptz default null,
    _payload_overrides jsonb default null,
    _extra_data        jsonb default null,
    _request_context   jsonb default null
) returns table(__invitation_id bigint, __uuid uuid, __on_create_actions jsonb)
    language plpgsql
as
$$
declare
    ___invitation_id bigint;
    ___uuid uuid;
    ___pending_actions jsonb;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.create_invitation');

    select * from unsecure.create_invitation_from_template(
        _created_by, _user_id, _correlation_id, _tenant_id, _template_code,
        _target_email, _message, _expires_at, _payload_overrides, _extra_data
    ) into ___invitation_id, ___uuid;

    perform unsecure.create_user_event(_created_by, _user_id, _correlation_id,
        'invitation_created', null, _request_context := _request_context,
        _event_data := jsonb_build_object('invitation_id', ___invitation_id, 'target_email', _target_email,
                                          'tenant_id', _tenant_id, 'template_code', _template_code));

    -- Process on_create phase actions immediately
    select coalesce(jsonb_agg(jsonb_build_object(
        'invitation_action_id', p.__invitation_action_id,
        'action_type_code', p.__action_type_code,
        'executor_code', p.__executor_code,
        'sequence', p.__sequence,
        'payload', p.__payload
    )), '[]'::jsonb)
    from unsecure.process_invitation_actions(
        _created_by, _user_id, _correlation_id, ___invitation_id, 'on_create'
    ) p
    into ___pending_actions;

    return query select ___invitation_id, ___uuid, ___pending_actions;
end;
$$;

-- ===========================================================================
-- 21. unsecure.create_invitation_template
-- ===========================================================================
create or replace function unsecure.create_invitation_template(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer,
    _code            text,
    _title           text,
    _description     text default null,
    _default_message text default null,
    _actions         jsonb default '[]'::jsonb
) returns table(__template_id integer)
    language plpgsql
as
$$
declare
    ___template_id integer;
    ___action jsonb;
begin
    insert into auth.invitation_template (created_by, updated_by, tenant_id, code, title, description, default_message)
    values (_created_by, _created_by, _tenant_id, _code, _title, _description, _default_message)
    returning template_id into ___template_id;

    for ___action in select * from jsonb_array_elements(_actions)
    loop
        insert into auth.invitation_template_action (
            created_by, updated_by, template_id, action_type_code, executor_code,
            phase_code, condition_code, sequence, is_required, payload_template
        ) values (
            _created_by, _created_by, ___template_id,
            ___action->>'action_type_code',
            coalesce(___action->>'executor_code',
                     (select executor_code from const.invitation_action_type where code = ___action->>'action_type_code')),
            coalesce(___action->>'phase_code', 'on_accept'),
            coalesce(___action->>'condition_code', 'always'),
            coalesce((___action->>'sequence')::integer, 0),
            coalesce((___action->>'is_required')::boolean, true),
            coalesce(___action->'payload_template', '{}'::jsonb)
        );
    end loop;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id,
        22010, 'invitation_template', ___template_id,
        jsonb_build_object('template_code', _code),
        _tenant_id);

    return query select ___template_id;
end;
$$;

-- ===========================================================================
-- 22. unsecure.update_invitation_template
-- ===========================================================================
create or replace function unsecure.update_invitation_template(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _template_id     integer,
    _title           text default null,
    _description     text default null,
    _default_message text default null,
    _is_active       boolean default null
) returns void
    language plpgsql
as
$$
declare
    ___tmpl record;
begin
    select template_id, code, tenant_id from auth.invitation_template where template_id = _template_id into ___tmpl;

    if ___tmpl is null then
        perform error.raise_39006(_template_id::text);
    end if;

    update auth.invitation_template
    set title = coalesce(_title, title),
        description = coalesce(_description, description),
        default_message = coalesce(_default_message, default_message),
        is_active = coalesce(_is_active, is_active),
        updated_by = _updated_by,
        updated_at = now()
    where template_id = _template_id;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id,
        22011, 'invitation_template', _template_id,
        jsonb_build_object('template_code', ___tmpl.code),
        ___tmpl.tenant_id);
end;
$$;

-- ===========================================================================
-- 23. unsecure.delete_invitation_template
-- ===========================================================================
create or replace function unsecure.delete_invitation_template(
    _deleted_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _template_id     integer
) returns void
    language plpgsql
as
$$
declare
    ___tmpl record;
begin
    select template_id, code, tenant_id from auth.invitation_template where template_id = _template_id into ___tmpl;

    if ___tmpl is null then
        perform error.raise_39006(_template_id::text);
    end if;

    delete from auth.invitation_template where template_id = _template_id;

    perform create_journal_message_for_entity(_deleted_by, _user_id, _correlation_id,
        22012, 'invitation_template', _template_id,
        jsonb_build_object('template_code', ___tmpl.code),
        ___tmpl.tenant_id);
end;
$$;

-- ===========================================================================
-- 24. auth.create_invitation_template
-- ===========================================================================
create or replace function auth.create_invitation_template(
    _created_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _tenant_id       integer,
    _code            text,
    _title           text,
    _description     text default null,
    _default_message text default null,
    _actions         jsonb default '[]'::jsonb,
    _request_context jsonb default null
) returns table(__template_id integer)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.manage_templates');

    return query select * from unsecure.create_invitation_template(
        _created_by, _user_id, _correlation_id, _tenant_id, _code, _title,
        _description, _default_message, _actions
    );
end;
$$;

-- ===========================================================================
-- 25. auth.update_invitation_template
-- ===========================================================================
create or replace function auth.update_invitation_template(
    _updated_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _template_id     integer,
    _title           text default null,
    _description     text default null,
    _default_message text default null,
    _is_active       boolean default null,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.manage_templates');

    perform unsecure.update_invitation_template(
        _updated_by, _user_id, _correlation_id, _template_id,
        _title, _description, _default_message, _is_active
    );
end;
$$;

-- ===========================================================================
-- 26. auth.delete_invitation_template
-- ===========================================================================
create or replace function auth.delete_invitation_template(
    _deleted_by      text,
    _user_id         bigint,
    _correlation_id  text,
    _template_id     integer,
    _request_context jsonb default null
) returns void
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'invitations.manage_templates');

    perform unsecure.delete_invitation_template(
        _deleted_by, _user_id, _correlation_id, _template_id
    );
end;
$$;
