/*
 * Invitation System — Schema, Seed Data, Error Functions, Permissions
 * ====================================================================
 *
 * 1. const.invitation_status — invitation status codes
 * 2. const.invitation_action_status — action status codes
 * 3. const.invitation_executor — executor types (database/backend/external)
 * 4. const.invitation_phase — action phases (on_create/on_accept)
 * 5. const.invitation_condition — pre-execution conditions
 * 6. const.invitation_action_type — registry of action types with executor
 * 7. auth.invitation — main invitation table
 * 8. auth.invitation_action — 1:N actions per invitation
 * 9. auth.invitation_template — reusable invitation templates
 * 10. auth.invitation_template_action — template action definitions
 * 11. New event codes and messages
 * 12. New error codes & functions (37001-37006)
 * 13. New permissions (invitations.*)
 * 14. Add invitation permissions to all existing assignable permission sets
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ---------------------------------------------------------------------------
-- 1. Invitation status codes
-- ---------------------------------------------------------------------------
create table if not exists const.invitation_status
(
    code text not null primary key
);

insert into const.invitation_status (code) values
    ('pending'),
    ('accepted'),
    ('rejected'),
    ('revoked'),
    ('expired'),
    ('processing'),
    ('completed'),
    ('failed')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. Invitation action status codes
-- ---------------------------------------------------------------------------
create table if not exists const.invitation_action_status
(
    code text not null primary key
);

insert into const.invitation_action_status (code) values
    ('pending'),
    ('processing'),
    ('completed'),
    ('failed'),
    ('skipped')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Executor types
-- ---------------------------------------------------------------------------
create table if not exists const.invitation_executor
(
    code  text not null primary key,
    title text not null
);

insert into const.invitation_executor (code, title) values
    ('database', 'Database — executed directly via SQL'),
    ('backend',  'Backend — executed by application server'),
    ('external', 'External — executed by external system')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 4. Action phases — when the action fires
-- ---------------------------------------------------------------------------
create table if not exists const.invitation_phase
(
    code  text not null primary key,
    title text not null
);

insert into const.invitation_phase (code, title) values
    ('on_create',  'On Create — fires immediately when invitation is created'),
    ('on_accept',  'On Accept — fires when the recipient accepts'),
    ('on_reject',  'On Reject — fires when the recipient rejects'),
    ('on_expired', 'On Expired — fires when the invitation expires')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 5. Pre-execution conditions — evaluated at execution time, skip if false
-- ---------------------------------------------------------------------------
create table if not exists const.invitation_condition
(
    code        text not null primary key,
    title       text not null,
    description text
);

insert into const.invitation_condition (code, title, description) values
    ('always',                  'Always',                      'Always execute this action'),
    ('user_not_in_tenant',      'User Not in Tenant',          'Execute only if the target user is not already a member of the invitation tenant'),
    ('user_not_in_group',       'User Not in Group',           'Execute only if the target user is not already a member of the specified group'),
    ('user_has_no_perm_set',    'User Has No Permission Set',  'Execute only if the target user does not already have the specified permission set'),
    ('user_has_no_resource_access','User Has No Resource Access','Execute only if the target user has no access to the specified resource')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 6. Invitation action type registry
-- ---------------------------------------------------------------------------
/*
 * const.invitation_action_type — Registry of action types
 *
 * payload_schema describes what fields the executor needs and where they come from.
 * Each field has:
 *   - type: "string" | "integer" | "boolean" | "array" | "object"
 *   - required: true/false
 *   - source: where to auto-populate from (null = must be in payload/overrides)
 *       "invitation.<column>"  — from auth.invitation record
 *       "payload.<key>"        — from the action's own payload (template + overrides)
 *
 * Example: {"fields": {"mobile_phone": {"type": "string", "required": true, "source": "invitation.target_email"}}}
 */
create table if not exists const.invitation_action_type
(
    code           text    not null primary key,
    title          text    not null,
    description    text,
    executor_code  text    not null references const.invitation_executor(code),
    payload_schema jsonb   not null default '{}'::jsonb,
    is_active      boolean not null default true,
    source         text    default null
);

insert into const.invitation_action_type (code, title, description, executor_code, payload_schema, source) values
    ('add_tenant_user', 'Add User to Tenant',
     'Adds the invited user as a tenant member',
     'database',
     '{"fields": {
         "tenant_id":      {"type": "integer", "required": true, "source": "invitation.tenant_id"},
         "target_user_id": {"type": "integer", "required": true, "source": "invitation.target_user_id"}
     }}'::jsonb, 'core'),

    ('add_group_member', 'Add User to Group',
     'Adds the invited user as a group member',
     'database',
     '{"fields": {
         "user_group_id":  {"type": "integer", "required": true,  "source": null},
         "target_user_id": {"type": "integer", "required": true,  "source": "invitation.target_user_id"},
         "tenant_id":      {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('assign_perm_set', 'Assign Permission Set',
     'Assigns a permission set to the invited user',
     'database',
     '{"fields": {
         "perm_set_code":  {"type": "string",  "required": true,  "source": null},
         "target_user_id": {"type": "integer", "required": true,  "source": "invitation.target_user_id"},
         "tenant_id":      {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('assign_permission', 'Assign Permission',
     'Assigns an individual permission to the invited user',
     'database',
     '{"fields": {
         "permission_code": {"type": "string",  "required": true,  "source": null},
         "target_user_id":  {"type": "integer", "required": true,  "source": "invitation.target_user_id"},
         "tenant_id":       {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('grant_resource_access', 'Grant Resource Access',
     'Grants resource-level access (ACL) to the invited user',
     'database',
     '{"fields": {
         "resource_type":  {"type": "string",  "required": true,  "source": null},
         "resource_id":    {"type": "integer", "required": true,  "source": null},
         "access_flags":   {"type": "array",   "required": false, "source": null},
         "target_user_id": {"type": "integer", "required": true,  "source": "invitation.target_user_id"},
         "tenant_id":      {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('send_welcome_email', 'Send Welcome Email',
     'Sends a welcome email to the invited user',
     'backend',
     '{"fields": {
         "email":           {"type": "string",  "required": true,  "source": "invitation.target_email"},
         "invitation_uuid": {"type": "string",  "required": true,  "source": "invitation.uuid"},
         "invitation_id":   {"type": "integer", "required": true,  "source": "invitation.invitation_id"},
         "inviter_user_id": {"type": "integer", "required": true,  "source": "invitation.inviter_user_id"},
         "message":         {"type": "string",  "required": false, "source": "invitation.message"},
         "tenant_id":       {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('notify_inviter', 'Notify Inviter',
     'Notifies the inviter that the invitation was accepted/rejected',
     'backend',
     '{"fields": {
         "inviter_user_id": {"type": "integer", "required": true,  "source": "invitation.inviter_user_id"},
         "target_email":    {"type": "string",  "required": true,  "source": "invitation.target_email"},
         "target_user_id":  {"type": "integer", "required": false, "source": "invitation.target_user_id"},
         "invitation_id":   {"type": "integer", "required": true,  "source": "invitation.invitation_id"},
         "status":          {"type": "string",  "required": true,  "source": "invitation.status_code"},
         "tenant_id":       {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core'),

    ('provision_external', 'Provision in External System',
     'Creates or provisions the user in an external system',
     'external',
     '{"fields": {
         "target_email":    {"type": "string",  "required": true,  "source": "invitation.target_email"},
         "target_user_id":  {"type": "integer", "required": false, "source": "invitation.target_user_id"},
         "invitation_uuid": {"type": "string",  "required": true,  "source": "invitation.uuid"},
         "tenant_id":       {"type": "integer", "required": true,  "source": "invitation.tenant_id"}
     }}'::jsonb, 'core')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 7. auth.invitation — main invitation table
-- ---------------------------------------------------------------------------
create table if not exists auth.invitation
(
    created_at       timestamptz default now()           not null,
    created_by       text        default 'unknown'::text not null,
    updated_at       timestamptz default now()           not null,
    updated_by       text        default 'unknown'::text not null,
    invitation_id    bigint generated always as identity
        primary key,
    tenant_id        integer     not null
        references auth.tenant on delete cascade,
    uuid             uuid        default ext.uuid_generate_v4() not null unique,
    inviter_user_id  bigint      not null
        references auth.user_info on delete cascade,
    target_email     text        not null,
    target_user_id   bigint
        references auth.user_info on delete set null,
    status_code      text        not null default 'pending'
        references const.invitation_status,
    message          text,
    token_id         bigint
        references auth.token on delete set null,
    expires_at       timestamptz not null,
    accepted_at      timestamptz,
    rejected_at      timestamptz,
    revoked_at       timestamptz,
    template_code    text,
    extra_data       jsonb,
    constraint invitation_created_by_check check (length(created_by) <= 250),
    constraint invitation_updated_by_check check (length(updated_by) <= 250)
);

create index if not exists ix_invitation_tenant     on auth.invitation (tenant_id);
create index if not exists ix_invitation_inviter    on auth.invitation (inviter_user_id);
create index if not exists ix_invitation_target     on auth.invitation (target_email);
create index if not exists ix_invitation_status     on auth.invitation (status_code) where status_code = 'pending';
create index if not exists ix_invitation_token      on auth.invitation (token_id) where token_id is not null;

-- ---------------------------------------------------------------------------
-- 8. auth.invitation_action — ordered actions per invitation
-- ---------------------------------------------------------------------------
create table if not exists auth.invitation_action
(
    created_at              timestamptz default now()           not null,
    created_by              text        default 'unknown'::text not null,
    updated_at              timestamptz default now()           not null,
    updated_by              text        default 'unknown'::text not null,
    invitation_action_id    bigint generated always as identity
        primary key,
    invitation_id           bigint      not null
        references auth.invitation on delete cascade,
    action_type_code        text        not null
        references const.invitation_action_type,
    executor_code           text        not null
        references const.invitation_executor,
    phase_code              text        not null default 'on_accept'
        references const.invitation_phase,
    condition_code          text        not null default 'always'
        references const.invitation_condition,
    sequence                integer     not null default 0,
    is_required             boolean     not null default true,
    status_code             text        not null default 'pending'
        references const.invitation_action_status,
    payload                 jsonb       not null default '{}'::jsonb,
    result_data             jsonb,
    error_message           text,
    completed_at            timestamptz,
    constraint invitation_action_created_by_check check (length(created_by) <= 250),
    constraint invitation_action_updated_by_check check (length(updated_by) <= 250)
);

create index if not exists ix_inv_action_invitation on auth.invitation_action (invitation_id);
create index if not exists ix_inv_action_status     on auth.invitation_action (invitation_id, sequence, status_code);

-- ---------------------------------------------------------------------------
-- 9. auth.invitation_template — reusable templates
-- ---------------------------------------------------------------------------
create table if not exists auth.invitation_template
(
    created_at     timestamptz default now()           not null,
    created_by     text        default 'unknown'::text not null,
    updated_at     timestamptz default now()           not null,
    updated_by     text        default 'unknown'::text not null,
    template_id    integer generated always as identity
        primary key,
    tenant_id      integer
        references auth.tenant on delete cascade,
    code           text        not null,
    title          text        not null,
    description    text,
    is_active      boolean     not null default true,
    default_message text,
    source         text        default null,
    unique (code, tenant_id),
    constraint inv_template_created_by_check check (length(created_by) <= 250),
    constraint inv_template_updated_by_check check (length(updated_by) <= 250)
);

-- ---------------------------------------------------------------------------
-- 10. auth.invitation_template_action — template action definitions
-- ---------------------------------------------------------------------------
create table if not exists auth.invitation_template_action
(
    created_at           timestamptz default now()           not null,
    created_by           text        default 'unknown'::text not null,
    updated_at           timestamptz default now()           not null,
    updated_by           text        default 'unknown'::text not null,
    template_action_id   integer generated always as identity
        primary key,
    template_id          integer     not null
        references auth.invitation_template on delete cascade,
    action_type_code     text        not null
        references const.invitation_action_type,
    executor_code        text        not null
        references const.invitation_executor,
    phase_code           text        not null default 'on_accept'
        references const.invitation_phase,
    condition_code       text        not null default 'always'
        references const.invitation_condition,
    sequence             integer     not null default 0,
    is_required          boolean     not null default true,
    payload_template     jsonb       not null default '{}'::jsonb,
    constraint inv_tmpl_action_created_by_check check (length(created_by) <= 250),
    constraint inv_tmpl_action_updated_by_check check (length(updated_by) <= 250)
);

create index if not exists ix_inv_tmpl_action_template on auth.invitation_template_action (template_id);

-- ---------------------------------------------------------------------------
-- 11. Event codes and messages
-- ---------------------------------------------------------------------------
insert into const.event_category (category_code, title, range_start, range_end, is_error, source) values
    ('invitation_event', 'Invitation Events', 22001, 22999, false, 'core'),
    ('invitation_error', 'Invitation Errors', 39001, 39999, true,  'core')
on conflict do nothing;

insert into const.event_code (event_id, code, category_code, title, description, is_system, source) values
    -- Invitation informational events (22001-22999)
    (22001, 'invitation_created',          'invitation_event', 'Invitation Created',          'New invitation was created', true, 'core'),
    (22002, 'invitation_accepted',         'invitation_event', 'Invitation Accepted',         'Invitation was accepted by the recipient', true, 'core'),
    (22003, 'invitation_rejected',         'invitation_event', 'Invitation Rejected',         'Invitation was rejected by the recipient', true, 'core'),
    (22004, 'invitation_revoked',          'invitation_event', 'Invitation Revoked',          'Invitation was revoked by the inviter', true, 'core'),
    (22005, 'invitation_expired',          'invitation_event', 'Invitation Expired',          'Invitation expired without response', true, 'core'),
    (22006, 'invitation_action_completed', 'invitation_event', 'Invitation Action Completed', 'An invitation action was completed', true, 'core'),
    (22007, 'invitation_action_failed',    'invitation_event', 'Invitation Action Failed',    'An invitation action failed', true, 'core'),
    (22008, 'invitation_completed',        'invitation_event', 'Invitation Completed',        'All invitation actions were completed', true, 'core'),
    (22009, 'invitation_failed',           'invitation_event', 'Invitation Failed',           'Invitation processing failed due to a required action failure', true, 'core'),
    (22010, 'invitation_template_created', 'invitation_event', 'Template Created',            'Invitation template was created', true, 'core'),
    (22011, 'invitation_template_updated', 'invitation_event', 'Template Updated',            'Invitation template was updated', true, 'core'),
    (22012, 'invitation_template_deleted', 'invitation_event', 'Template Deleted',            'Invitation template was deleted', true, 'core'),
    -- Invitation errors (39001-39999)
    (39001, 'err_invitation_not_found',    'invitation_error', 'Invitation Not Found',        'Invitation does not exist', true, 'core'),
    (39002, 'err_invitation_not_pending',  'invitation_error', 'Invitation Not Pending',      'Invitation is not in pending state', true, 'core'),
    (39003, 'err_invitation_expired',      'invitation_error', 'Invitation Expired',          'Invitation has expired', true, 'core'),
    (39004, 'err_invitation_action_not_found','invitation_error','Invitation Action Not Found','Invitation action does not exist', true, 'core'),
    (39005, 'err_invitation_action_not_pending','invitation_error','Invitation Action Not Pending','Invitation action is not in pending or processing state', true, 'core'),
    (39006, 'err_invitation_template_not_found','invitation_error','Template Not Found',       'Invitation template does not exist or is inactive', true, 'core')
on conflict do nothing;

insert into const.event_message (event_id, language_code, message_template) values
    -- Invitation event messages
    (22001, 'en', 'Invitation was sent to "{target_email}" for tenant "{tenant_title}" by {actor}'),
    (22002, 'en', 'Invitation to tenant "{tenant_title}" was accepted by "{target_email}"'),
    (22003, 'en', 'Invitation to tenant "{tenant_title}" was rejected by "{target_email}"'),
    (22004, 'en', 'Invitation to "{target_email}" was revoked by {actor}'),
    (22005, 'en', 'Invitation to "{target_email}" for tenant "{tenant_title}" expired'),
    (22006, 'en', 'Invitation action "{action_type}" completed for "{target_email}"'),
    (22007, 'en', 'Invitation action "{action_type}" failed for "{target_email}": {error_message}'),
    (22008, 'en', 'All actions completed for invitation to "{target_email}"'),
    (22009, 'en', 'Invitation to "{target_email}" failed: required action "{action_type}" failed'),
    (22010, 'en', 'Invitation template "{template_code}" was created by {actor}'),
    (22011, 'en', 'Invitation template "{template_code}" was updated by {actor}'),
    (22012, 'en', 'Invitation template "{template_code}" was deleted by {actor}'),
    -- Invitation error messages
    (39001, 'en', 'Invitation (id: {invitation_id}) does not exist'),
    (39002, 'en', 'Invitation (id: {invitation_id}) is not in pending state (current: {status_code})'),
    (39003, 'en', 'Invitation (id: {invitation_id}) has expired'),
    (39004, 'en', 'Invitation action (id: {invitation_action_id}) does not exist'),
    (39005, 'en', 'Invitation action (id: {invitation_action_id}) is not in pending or processing state'),
    (39006, 'en', 'Invitation template (code: {template_code}) does not exist or is inactive')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 12. Error functions (39001-39006)
-- ---------------------------------------------------------------------------
create or replace function error.raise_39001(_invitation_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation (id: %) does not exist', _invitation_id
        using errcode = '39001';
end;
$$;

create or replace function error.raise_39002(_invitation_id bigint, _status_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation (id: %) is not in pending state (current: %)', _invitation_id, _status_code
        using errcode = '39002';
end;
$$;

create or replace function error.raise_39003(_invitation_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation (id: %) has expired', _invitation_id
        using errcode = '39003';
end;
$$;

create or replace function error.raise_39004(_invitation_action_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation action (id: %) does not exist', _invitation_action_id
        using errcode = '39004';
end;
$$;

create or replace function error.raise_39005(_invitation_action_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation action (id: %) is not in pending or processing state', _invitation_action_id
        using errcode = '39005';
end;
$$;

create or replace function error.raise_39006(_template_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Invitation template (code: %) does not exist or is inactive', _template_code
        using errcode = '39006';
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Invitation permissions
-- ---------------------------------------------------------------------------
select * from unsecure.create_permission_as_system('Invitations', '', false, null, 'core');
select * from unsecure.create_permission_as_system('Create invitation', 'invitations', true, null, 'core');
select * from unsecure.create_permission_as_system('Accept invitation', 'invitations', true, null, 'core');
select * from unsecure.create_permission_as_system('Reject invitation', 'invitations', true, null, 'core');
select * from unsecure.create_permission_as_system('Revoke invitation', 'invitations', true, null, 'core');
select * from unsecure.create_permission_as_system('Get invitations', 'invitations', true, null, 'core');
select * from unsecure.create_permission_as_system('Manage templates', 'invitations', true, null, 'core');

-- ---------------------------------------------------------------------------
-- 14. Add invitation permissions to all existing assignable permission sets
-- ---------------------------------------------------------------------------
do $$
declare
    __ps record;
    __inv_perms text[] := array[
        'invitations.create_invitation', 'invitations.accept_invitation',
        'invitations.reject_invitation', 'invitations.revoke_invitation',
        'invitations.get_invitations', 'invitations.manage_templates'
    ];
begin
    for __ps in
        select perm_set_id, tenant_id
        from auth.perm_set
        where is_assignable = true
    loop
        perform unsecure.add_perm_set_permissions(
            'system', 1, null,
            __ps.perm_set_id, __inv_perms, __ps.tenant_id
        );
    end loop;
end;
$$;
