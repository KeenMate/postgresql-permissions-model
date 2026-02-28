/*
 * Error Functions
 * ===============
 *
 * Error raising functions with structured error codes
 *
 * Error Code Ranges:
 * - 30001-30999: Security/auth errors
 * - 31001-31999: Validation errors
 * - 32001-32999: Permission errors
 * - 33001-33999: User/group errors
 * - 34001-34999: Tenant errors
 * - 35001-35999: Resource access errors
 * - 36001-36999: Token config errors
 *
 * This file is part of the PostgreSQL Permissions Model v2
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

/*
 * Security/Auth Errors (30001-30999)
 */

-- 30001: API key/secret invalid
create or replace function error.raise_30001(_api_key text) returns void
    language plpgsql
as
$$
begin
    raise exception 'API key/secret (key: %) combination is not valid or API user has not been found', _api_key
        using errcode = '30001';
end;
$$;

-- 30002: Token invalid or expired
create or replace function error.raise_30002(_token_uid text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Token (uid: %) is not valid or has expired', _token_uid
        using errcode = '30002';
end;
$$;

-- 30003: Token belongs to different user
create or replace function error.raise_30003(_token_uid text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Token (uid: %) was created for different user', _token_uid
        using errcode = '30003';
end;
$$;

-- 30004: Token already used
create or replace function error.raise_30004() returns void
    language plpgsql
as
$$
begin
    raise exception 'The same token is already used'
        using errcode = '30004';
end;
$$;

-- 30005: Token not found
create or replace function error.raise_30005() returns void
    language plpgsql
as
$$
begin
    raise exception 'Token does not exist'
        using errcode = '30005';
end;
$$;

/*
 * Validation Errors (31001-31999)
 */

-- 31001: Either group or user required
create or replace function error.raise_31001() returns void
    language plpgsql
as
$$
begin
    raise exception 'Either user group id or target user id must not be null'
        using errcode = '31001';
end;
$$;

-- 31002: Either perm set or permission required
create or replace function error.raise_31002() returns void
    language plpgsql
as
$$
begin
    raise exception 'Either permission set code or permission code must not be null'
        using errcode = '31002';
end;
$$;

-- 31003: Either permission id or code required
create or replace function error.raise_31003() returns void
    language plpgsql
as
$$
begin
    raise exception 'Either permission id or code has to be not null'
        using errcode = '31003';
end;
$$;

-- 31004: Either mapping id or role required
create or replace function error.raise_31004() returns void
    language plpgsql
as
$$
begin
    raise exception 'Either mapped object id or mapped role must not be empty'
        using errcode = '31004';
end;
$$;

-- 31010: Event code is system
create or replace function error.raise_31010(_event_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'Event code (event_id: %) is a system event and cannot be modified or deleted', _event_id
        using errcode = '31010';
end;
$$;

-- 31011: Event code not found
create or replace function error.raise_31011(_event_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'Event code (event_id: %) does not exist', _event_id
        using errcode = '31011';
end;
$$;

-- 31012: Event category not empty
create or replace function error.raise_31012(_category_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Event category (code: %) still has event codes and cannot be deleted', _category_code
        using errcode = '31012';
end;
$$;

-- 31013: Event ID out of range
create or replace function error.raise_31013(_event_id integer, _category_code text, _range_start integer, _range_end integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'Event ID % is outside the allowed range (%-%) for category "%"', _event_id, _range_start, _range_end, _category_code
        using errcode = '31013';
end;
$$;

-- 31014: Event category not found
create or replace function error.raise_31014(_category_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Event category (code: %) does not exist', _category_code
        using errcode = '31014';
end;
$$;

/*
 * Permission Errors (32001-32999)
 */

-- 32001: No permission
create or replace function error.raise_32001(_user_id bigint, _perm_codes text[], _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    raise exception 'User(id: %) has no permission (codes: %) in tenant(id: %)', _user_id, array_to_string(_perm_codes, '; '), _tenant_id
        using errcode = '32001';
end;
$$;

-- 32002: Permission not found
create or replace function error.raise_32002(_permission_full_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Permission (code: %) does not exist', _permission_full_code
        using errcode = '32002';
end;
$$;

-- 32003: Permission not assignable
create or replace function error.raise_32003(_permission_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Permission (code: %) is not assignable', _permission_code
        using errcode = '32003';
end;
$$;

-- 32004: Permission set not found
create or replace function error.raise_32004(_perm_set_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Permission set (code: %) does not exist', _perm_set_code
        using errcode = '32004';
end;
$$;

-- 32005: Permission set not assignable
create or replace function error.raise_32005(_perm_set_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Permission set (code: %) is not assignable', _perm_set_code
        using errcode = '32005';
end;
$$;

-- 32006: Permission set wrong tenant
create or replace function error.raise_32006(_perm_set_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    raise exception 'Permission set (id: %) is not defined in tenant (id: %)', _perm_set_id, _tenant_id
        using errcode = '32006';
end;
$$;

-- 32007: Parent permission not found
create or replace function error.raise_32007(_parent_full_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Parent permission (code: %) does not exist', _parent_full_code
        using errcode = '32007';
end;
$$;

-- 32008: Some permissions not assignable
create or replace function error.raise_32008() returns void
    language plpgsql
as
$$
begin
    raise exception 'Some permissions are not assignable'
        using errcode = '32008';
end;
$$;

/*
 * User/Group Errors (33001-33999)
 */

-- 33001: User not found
create or replace function error.raise_33001(_user_id bigint, _email text DEFAULT NULL::text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (user id: %, email: %) does not exist', _user_id, _email
        using errcode = '33001';
end;
$$;

-- 33002: User is system
create or replace function error.raise_33002(_user_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (user id: %) is a system user', _user_id
        using errcode = '33002';
end;
$$;

-- 33003: User not active
create or replace function error.raise_33003(_user_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (id: %) is not in active state', _user_id
        using errcode = '33003';
end;
$$;

-- 33004: User locked
create or replace function error.raise_33004(_email text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (email: %) is locked out', _email
        using errcode = '33004';
end;
$$;

-- 33004: User locked (by user_id)
create or replace function error.raise_33004(_user_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (id: %) is locked out', _user_id
        using errcode = '33004';
end;
$$;

-- 33005: User cannot login
create or replace function error.raise_33005(_user_id bigint) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (id: %) is not supposed to log in', _user_id
        using errcode = '33005';
end;
$$;

-- 33006: User no email provider
create or replace function error.raise_33006(_username text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (username: %) cannot be ensured for email provider, use registration for that', _username
        using errcode = '33006';
end;
$$;

-- 33007: Identity already used
create or replace function error.raise_33007(_normalized_email text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User identity (uid: %) is already in use', _normalized_email
        using errcode = '33007';
end;
$$;

-- 33008: Identity not active
create or replace function error.raise_33008(_user_id bigint, _provider_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (id: %) identity for provider (code: %) is not in active state', _user_id, _provider_code
        using errcode = '33008';
end;
$$;

-- 33009: Identity not found
create or replace function error.raise_33009(_user_id bigint, _provider_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (id: %) identity for provider (code: %) does not exist', _user_id, _provider_code
        using errcode = '33009';
end;
$$;

-- 33010: Provider not active
create or replace function error.raise_33010(_provider_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Provider (provider code: %) is not in active state', _provider_code
        using errcode = '33010';
end;
$$;

-- 33011: Group not found
create or replace function error.raise_33011(_user_group_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'User group (group id: %) does not exist', _user_group_id
        using errcode = '33011';
end;
$$;

-- 33012: Group not active
create or replace function error.raise_33012(_user_group_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'User group (group id: %) is not active', _user_group_id
        using errcode = '33012';
end;
$$;

-- 33013: Group not assignable
create or replace function error.raise_33013(_user_group_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'User group (group id: %) is either not assignable or is external', _user_group_id
        using errcode = '33013';
end;
$$;

-- 33014: Group is system
create or replace function error.raise_33014(_user_group_id integer) returns void
    language plpgsql
as
$$
begin
    raise exception 'User group (group id: %) is a system group', _user_group_id
        using errcode = '33014';
end;
$$;

-- 33015: Not owner
create or replace function error.raise_33015(_user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (uid: %) is not tenant (id: %) or user group (id: %) owner', _user_id, _tenant_id, _user_group_id
        using errcode = '33015';
end;
$$;

-- 33016: Provider does not allow group mapping
create or replace function error.raise_33016(_provider_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Provider (code: %) does not allow group mapping', _provider_code
        using errcode = '33016';
end;
$$;

-- 33017: Provider does not allow group sync
create or replace function error.raise_33017(_provider_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Provider (code: %) does not allow group sync', _provider_code
        using errcode = '33017';
end;
$$;

/*
 * Tenant Errors (34001-34999)
 */

-- 34001: No tenant access
create or replace function error.raise_34001(_tenant_id text, _username text) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (username: %) has no access to tenant (id: %)', _username, _tenant_id
        using errcode = '34001';
end;
$$;

/*
 * Resource Access Errors (35001-35999)
 */

-- 35001: No access to resource
create or replace function error.raise_35001(_user_id bigint, _resource_type text, _resource_id bigint, _tenant_id integer default 1) returns void
    language plpgsql
as
$$
begin
    raise exception 'User (uid: %) has no access to resource (type: %, id: %) in tenant (id: %)', _user_id, _resource_type, _resource_id, _tenant_id
        using errcode = '35001';
end;
$$;

-- 35002: Either user_id or user_group_id required
create or replace function error.raise_35002() returns void
    language plpgsql
as
$$
begin
    raise exception 'Either target user_id or user_group_id must be provided'
        using errcode = '35002';
end;
$$;

-- 35003: Resource type not found or inactive
create or replace function error.raise_35003(_resource_type text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Resource type (code: %) does not exist or is not active', _resource_type
        using errcode = '35003';
end;
$$;

-- 35004: Access flag not found
create or replace function error.raise_35004(_access_flag text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Access flag (code: %) does not exist', _access_flag
        using errcode = '35004';
end;
$$;

/*
 * Token Config Errors (36001-36999)
 */

-- 36001: Token type not found
create or replace function error.raise_36001(_token_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Token type (code: %) does not exist', _token_type_code
        using errcode = '36001';
end;
$$;

-- 36002: Token type is system
create or replace function error.raise_36002(_token_type_code text) returns void
    language plpgsql
as
$$
begin
    raise exception 'Token type (code: %) is a system token type and cannot be modified or deleted', _token_type_code
        using errcode = '36002';
end;
$$;

/*
 * Backwards Compatibility Aliases
 * ===============================
 * These functions maintain the old naming convention for backwards compatibility.
 * They simply call the new functions.
 */

-- User errors (52xxx -> 33xxx)
create or replace function error.raise_52101(_username text) returns void language sql as $$ select error.raise_33006(_username); $$;
create or replace function error.raise_52102(_normalized_email text) returns void language sql as $$ select error.raise_33007(_normalized_email); $$;
create or replace function error.raise_52103(_user_id bigint, _email text DEFAULT NULL) returns void language sql as $$ select error.raise_33001(_user_id, _email); $$;
create or replace function error.raise_52104(_user_id bigint) returns void language sql as $$ select error.raise_33002(_user_id); $$;
create or replace function error.raise_52105(_user_id bigint) returns void language sql as $$ select error.raise_33003(_user_id); $$;
create or replace function error.raise_52106(_email text) returns void language sql as $$ select error.raise_33004(_email); $$;
create or replace function error.raise_52107(_provider_code text) returns void language sql as $$ select error.raise_33010(_provider_code); $$;
create or replace function error.raise_52108(_tenant_id text, _username text) returns void language sql as $$ select error.raise_34001(_tenant_id, _username); $$;
create or replace function error.raise_52109(_user_id bigint, _perm_codes text[], _tenant_id integer DEFAULT 1) returns void language sql as $$ select error.raise_32001(_user_id, _perm_codes, _tenant_id); $$;
create or replace function error.raise_52110(_user_id bigint, _provider_code text) returns void language sql as $$ select error.raise_33008(_user_id, _provider_code); $$;
create or replace function error.raise_52111(_user_id bigint, _provider_code text) returns void language sql as $$ select error.raise_33009(_user_id, _provider_code); $$;
create or replace function error.raise_52112(_user_id bigint) returns void language sql as $$ select error.raise_33005(_user_id); $$;

-- Group errors
create or replace function error.raise_52171(_user_group_id integer) returns void language sql as $$ select error.raise_33011(_user_group_id); $$;
create or replace function error.raise_52172(_user_group_id integer) returns void language sql as $$ select error.raise_33012(_user_group_id); $$;
create or replace function error.raise_52173(_user_group_id integer) returns void language sql as $$ select error.raise_33013(_user_group_id); $$;
create or replace function error.raise_52174() returns void language sql as $$ select error.raise_31004(); $$;
create or replace function error.raise_52175(_perm_set_code text) returns void language sql as $$ select error.raise_32005(_perm_set_code); $$;
create or replace function error.raise_52176(_perm_set_code text) returns void language sql as $$ select error.raise_32003(_perm_set_code); $$;
create or replace function error.raise_52177(_perm_set_id integer, _tenant_id integer DEFAULT 1) returns void language sql as $$ select error.raise_32006(_perm_set_id, _tenant_id); $$;
create or replace function error.raise_52178() returns void language sql as $$ select error.raise_32008(); $$;
create or replace function error.raise_52179(_parent_full_code text) returns void language sql as $$ select error.raise_32007(_parent_full_code); $$;

-- Validation errors
create or replace function error.raise_52271(_user_group_id integer) returns void language sql as $$ select error.raise_33014(_user_group_id); $$;
create or replace function error.raise_52272() returns void language sql as $$ select error.raise_31001(); $$;
create or replace function error.raise_52273() returns void language sql as $$ select error.raise_31002(); $$;
create or replace function error.raise_52274() returns void language sql as $$ select error.raise_31003(); $$;
create or replace function error.raise_52275(_permission_full_code text) returns void language sql as $$ select error.raise_32002(_permission_full_code); $$;

-- Token errors
create or replace function error.raise_52276() returns void language sql as $$ select error.raise_30004(); $$;
create or replace function error.raise_52277() returns void language sql as $$ select error.raise_30005(); $$;
create or replace function error.raise_52278(_token_uid text) returns void language sql as $$ select error.raise_30002(_token_uid); $$;
create or replace function error.raise_52279(_token_uid text) returns void language sql as $$ select error.raise_30003(_token_uid); $$;

-- Permission errors
create or replace function error.raise_52180(_permission_code text) returns void language sql as $$ select error.raise_32002(_permission_code); $$;
create or replace function error.raise_52181(_permission_code text) returns void language sql as $$ select error.raise_32003(_permission_code); $$;
create or replace function error.raise_52282(_perm_set_code text) returns void language sql as $$ select error.raise_32004(_perm_set_code); $$;
create or replace function error.raise_52283(_perm_set_code text) returns void language sql as $$ select error.raise_32005(_perm_set_code); $$;

-- API key errors
create or replace function error.raise_52301(_api_key text) returns void language sql as $$ select error.raise_30001(_api_key); $$;

-- Provider capability errors
create or replace function error.raise_52113(_provider_code text) returns void language sql as $$ select error.raise_33016(_provider_code); $$;
create or replace function error.raise_52114(_provider_code text) returns void language sql as $$ select error.raise_33017(_provider_code); $$;

-- Owner errors
create or replace function error.raise_52401(_user_id bigint, _user_group_id integer, _tenant_id integer DEFAULT 1) returns void language sql as $$ select error.raise_33015(_user_id, _user_group_id, _tenant_id); $$;

