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

create or replace function auth.create_user_event(_created_by text, _user_id bigint, _correlation_id text, _event_type_code text, _target_user_id bigint, _ip_address text DEFAULT NULL::text, _user_agent text DEFAULT NULL::text, _origin text DEFAULT NULL::text, _event_data jsonb DEFAULT NULL::jsonb, _target_user_oid text DEFAULT NULL::text, _target_username text DEFAULT NULL::text)
    returns TABLE(___user_event_id bigint)
    language plpgsql
as
$$
begin
	return query
		select __user_event_id
		from unsecure.create_user_event(_created_by, _user_id, _correlation_id, _event_type_code,
																		_target_user_id, _ip_address,
																		_user_agent, _origin, _event_data, _target_user_oid, _target_username);
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
        __ip_address text,
        __user_agent text,
        __origin text,
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
                 , count(1) over () as total_items
            from auth.user_event ue
            where (_event_type_code is null or ue.event_type_code = _event_type_code)
              and (_target_user_id is null or ue.target_user_id = _target_user_id)
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
             , ue.ip_address
             , ue.user_agent
             , ue.origin
             , ue.event_data
             , ue.correlation_id
             , ue.created_at
             , ue.created_by
             , fr.total_items
        from filtered_rows fr
        join auth.user_event ue on ue.user_event_id = fr.user_event_id
        order by ue.created_at desc;
end;
$$;

