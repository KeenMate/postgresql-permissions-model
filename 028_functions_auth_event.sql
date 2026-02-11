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

create or replace function auth.create_user_event(_created_by text, _user_id bigint, _event_type_code text, _target_user_id bigint, _ip_address text DEFAULT NULL::text, _user_agent text DEFAULT NULL::text, _origin text DEFAULT NULL::text, _event_data jsonb DEFAULT NULL::jsonb, _target_user_oid text DEFAULT NULL::text, _target_username text DEFAULT NULL::text)
    returns TABLE(___user_event_id bigint)
    language plpgsql
as
$$
begin
	return query
		select __user_event_id
		from unsecure.create_user_event(_created_by, _user_id, _event_type_code,
																		_target_user_id, _ip_address,
																		_user_agent, _origin, _event_data, _target_user_oid, _target_username);
end;
$$;

