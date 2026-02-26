/*
 * Auth Event Functions
 * ====================
 *
 * Audit event logging
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

create or replace function auth.create_user_event(_created_by text, _user_id bigint, _correlation_id text, _event_type_code text, _target_user_id bigint, _request_context jsonb DEFAULT NULL::jsonb, _event_data jsonb DEFAULT NULL::jsonb, _target_user_oid text DEFAULT NULL::text, _target_username text DEFAULT NULL::text)
    returns TABLE(___user_event_id bigint)
    language plpgsql
as
$$
begin
	return query
		select __user_event_id
		from unsecure.create_user_event(_created_by, _user_id, _correlation_id, _event_type_code,
																		_target_user_id, _request_context,
																		_event_data, _target_user_oid, _target_username);
end;
$$;

/*
 * Search User Events
 * ==================
 *
 * Paginated search of user events with optional filters.
 * Requires 'authentication.read_user_events' permission.
 */
create or replace function auth.search_user_events(
    _user_id bigint,
    _correlation_id text default null,
    _event_type_code text default null,
    _target_user_id bigint default null,
    _request_context_criteria jsonb default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _page integer default 1,
    _page_size integer default 10
)
    returns table(
        __user_event_id bigint,
        __event_type_code text,
        __requester_user_id bigint,
        __requester_username text,
        __target_user_id bigint,
        __target_username text,
        __target_user_oid text,
        __request_context jsonb,
        __event_data jsonb,
        __correlation_id text,
        __created_at timestamptz,
        __created_by text,
        __total_items bigint
    )
    stable
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'authentication.read_user_events');

    return query
        with filtered_rows as (
            select ue.user_event_id
                 , ue.created_at as event_created_at
                 , count(1) over () as total_items
            from auth.user_event ue
            where (_event_type_code is null or ue.event_type_code = _event_type_code)
              and (_target_user_id is null or ue.target_user_id = _target_user_id)
              and (_request_context_criteria is null or ue.request_context @> _request_context_criteria)
              and (_correlation_id is null or ue.correlation_id = _correlation_id)
              and ue.created_at between coalesce(_from, now() - interval '100 years')
                                    and coalesce(_to, now() + interval '100 years')
            order by ue.created_at desc
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select ue.user_event_id
             , ue.event_type_code
             , ue.requester_user_id
             , ue.requester_username
             , ue.target_user_id
             , ue.target_username
             , ue.target_user_oid
             , ue.request_context
             , ue.event_data
             , ue.correlation_id
             , ue.created_at
             , ue.created_by
             , fr.total_items
        from filtered_rows fr
        join auth.user_event ue on ue.user_event_id = fr.user_event_id and ue.created_at = fr.event_created_at
        order by ue.created_at desc;
end;
$$;

/*
 * Get User Audit Trail
 * ====================
 *
 * Combined view of journal entries and user events for a specific user.
 * Returns a unified, paginated timeline of all audit activity related to a user.
 * Requires 'authentication.read_user_events' permission.
 */
create or replace function auth.get_user_audit_trail(
    _user_id bigint,
    _correlation_id text default null,
    _target_user_id bigint default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _page integer default 1,
    _page_size integer default 20
) returns table(
    __source text,
    __event_id integer,
    __event_type_code text,
    __event_category text,
    __message text,
    __request_context jsonb,
    __event_data jsonb,
    __correlation_id text,
    __created_at timestamptz,
    __created_by text,
    __total_items bigint
)
    stable
    language plpgsql
as
$$
declare
    __from timestamptz;
    __to timestamptz;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'authentication.read_user_events');

    __from := coalesce(_from, now() - interval '100 years');
    __to := coalesce(_to, now() + interval '100 years');

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 20), 100);

    return query
        with combined as (
            -- Journal entries where keys contain the target user
            select 'journal'::text as source
                 , j.event_id
                 , ec.code as event_type_code
                 , ec.category_code as event_category
                 , format_journal_message(
                       get_event_message_template(j.event_id),
                       j.data_payload,
                       j.created_by
                   ) as message
                 , j.request_context
                 , j.data_payload as event_data
                 , j.correlation_id
                 , j.created_at
                 , j.created_by
            from public.journal j
            left join const.event_code ec on ec.event_id = j.event_id
            where j.keys @> jsonb_build_object('user', _target_user_id)
              and j.created_at between __from and __to

            union all

            -- User events where target_user_id matches
            select 'user_event'::text as source
                 , null::integer as event_id
                 , ue.event_type_code
                 , 'user_event'::text as event_category
                 , null::text as message
                 , ue.request_context
                 , ue.event_data
                 , ue.correlation_id
                 , ue.created_at
                 , ue.created_by
            from auth.user_event ue
            where ue.target_user_id = _target_user_id
              and ue.created_at between __from and __to
        ),
        counted as (
            select *, count(1) over () as total_items
            from combined
            order by created_at desc
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select c.source
             , c.event_id
             , c.event_type_code
             , c.event_category
             , c.message
             , c.request_context
             , c.event_data
             , c.correlation_id
             , c.created_at
             , c.created_by
             , c.total_items
        from counted c
        order by c.created_at desc;
end;
$$;

/*
 * Get Security Events
 * ===================
 *
 * Aggregated view of security-relevant events: failed logins, lockouts,
 * disables, and permission denials. Paginated.
 * Requires 'authentication.read_user_events' permission.
 */
create or replace function auth.get_security_events(
    _user_id bigint,
    _correlation_id text default null,
    _from timestamptz default null,
    _to timestamptz default null,
    _page integer default 1,
    _page_size integer default 20
) returns table(
    __source text,
    __event_type_code text,
    __requester_user_id bigint,
    __requester_username text,
    __target_user_id bigint,
    __target_username text,
    __request_context jsonb,
    __event_data jsonb,
    __correlation_id text,
    __created_at timestamptz,
    __total_items bigint
)
    stable
    language plpgsql
as
$$
declare
    __from timestamptz;
    __to timestamptz;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'authentication.read_user_events');

    __from := coalesce(_from, now() - interval '100 years');
    __to := coalesce(_to, now() + interval '100 years');

    _page := coalesce(_page, 1);
    _page_size := least(coalesce(_page_size, 20), 100);

    return query
        with security_events as (
            -- User events: failed logins, lockouts, disables
            select 'user_event'::text as source
                 , ue.event_type_code
                 , ue.requester_user_id
                 , ue.requester_username
                 , ue.target_user_id
                 , ue.target_username
                 , ue.request_context
                 , ue.event_data
                 , ue.correlation_id
                 , ue.created_at
            from auth.user_event ue
            where ue.event_type_code in ('user_login_failed', 'user_locked', 'user_disabled',
                                         'user_unlocked', 'user_enabled', 'identity_disabled',
                                         'identity_enabled')
              and ue.created_at between __from and __to

            union all

            -- Journal: permission denials
            select 'journal'::text as source
                 , ec.code as event_type_code
                 , j.user_id as requester_user_id
                 , j.created_by as requester_username
                 , (j.keys ->> 'user')::bigint as target_user_id
                 , null::text as target_username
                 , j.request_context
                 , j.data_payload as event_data
                 , j.correlation_id
                 , j.created_at
            from public.journal j
            inner join const.event_code ec on ec.event_id = j.event_id
            where j.event_id = 32001  -- err_no_permission
              and j.created_at between __from and __to
        ),
        counted as (
            select *, count(1) over () as total_items
            from security_events
            order by created_at desc
            offset ((_page - 1) * _page_size) limit _page_size
        )
        select c.source
             , c.event_type_code
             , c.requester_user_id
             , c.requester_username
             , c.target_user_id
             , c.target_username
             , c.request_context
             , c.event_data
             , c.correlation_id
             , c.created_at
             , c.total_items
        from counted c
        order by c.created_at desc;
end;
$$;

