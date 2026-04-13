/*
 * Seed Data
 * =========
 *
 * Initial data inserts for const tables and system records
 *
 * This file is part of the PostgreSQL Permissions Model v2
 * Generated from WHOLE_DB.sql
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- Token types
INSERT INTO const.token_type (code, default_expiration_in_seconds, is_system) VALUES
    ('password_reset', 3600, true),
    ('email_verification', 86400, true),
    ('invite', 604800, true),
    ('mfa', 300, true)
ON CONFLICT DO NOTHING;

-- Token channels
INSERT INTO const.token_channel (code) VALUES
    ('email'),
    ('sms'),
    ('app')
ON CONFLICT DO NOTHING;

-- Token states
INSERT INTO const.token_state (code) VALUES
    ('valid'),
    ('used'),
    ('expired'),
    ('failed'),
    ('validation_failed')
ON CONFLICT DO NOTHING;

-- User types
INSERT INTO const.user_type (code) VALUES
    ('normal'),
    ('system'),
    ('service'),
    ('api')
ON CONFLICT DO NOTHING;

-- Tenant access types
INSERT INTO const.tenant_access_type (code) VALUES
    ('public'),
    ('authenticated'),
    ('private')
ON CONFLICT DO NOTHING;

-- User group member types
INSERT INTO const.user_group_member_type (code) VALUES
    ('manual'),
    ('external'),
    ('synced')
ON CONFLICT DO NOTHING;

-- System parameters
INSERT INTO const.sys_param (group_code, code, text_value) VALUES
    ('journal', 'level', 'update'),  -- 'all', 'update', or 'none'
    ('journal', 'retention_days', '365'),
    ('journal', 'storage_mode', 'local'),        -- 'local', 'notify', or 'both'
    ('user_event', 'retention_days', '365'),
    ('user_event', 'storage_mode', 'local')       -- 'local', 'notify', or 'both'
ON CONFLICT DO NOTHING;

INSERT INTO const.sys_param (group_code, code, text_value, number_value) VALUES
    ('partition', 'months_ahead', '3', 3)
ON CONFLICT DO NOTHING;

/*
 * Event Categories
 * ================
 *
 * 10000-19999  Informational events
 * 30000-39999  Errors
 * 50000+       Application reserved
 */
INSERT INTO const.event_category (category_code, range_start, range_end, is_error, source) VALUES
    -- Informational events (10xxx)
    ('user_event',        10001, 10999, false, 'core'),
    ('tenant_event',      11001, 11999, false, 'core'),
    ('permission_event',  12001, 12999, false, 'core'),
    ('group_event',       13001, 13999, false, 'core'),
    ('apikey_event',      14001, 14999, false, 'core'),
    ('token_event',       15001, 15999, false, 'core'),
    ('provider_event',    16001, 16999, false, 'core'),
    ('maintenance_event', 17001, 17999, false, 'core'),
    ('resource_event',    18001, 18999, false, 'core'),
    ('token_config_event',19001, 19999, false, 'core'),
    -- Errors (30xxx)
    ('security_error',    30001, 30999, true, 'core'),
    ('validation_error',  31001, 31999, true, 'core'),
    ('permission_error',  32001, 32999, true, 'core'),
    ('user_error',        33001, 33999, true, 'core'),
    ('tenant_error',      34001, 34999, true, 'core'),
    ('resource_error',    35001, 35999, true, 'core'),
    ('token_config_error',36001, 36999, true, 'core')
ON CONFLICT DO NOTHING;

/*
 * Event Codes - Informational Events (10xxx)
 */
INSERT INTO const.event_code (event_id, code, category_code, is_system, source) VALUES
    -- User events (10001-10999)
    (10001, 'user_created',           'user_event', true, 'core'),
    (10002, 'user_updated',           'user_event', true, 'core'),
    (10003, 'user_deleted',           'user_event', true, 'core'),
    (10004, 'user_enabled',           'user_event', true, 'core'),
    (10005, 'user_disabled',          'user_event', true, 'core'),
    (10006, 'user_locked',            'user_event', true, 'core'),
    (10007, 'user_unlocked',          'user_event', true, 'core'),
    (10008, 'user_registered',        'user_event', true, 'core'),
    (10010, 'user_logged_in',         'user_event', true, 'core'),
    (10011, 'user_logged_out',        'user_event', true, 'core'),
    (10012, 'user_login_failed',      'user_event', true, 'core'),
    (10020, 'password_changed',       'user_event', true, 'core'),
    (10021, 'password_reset_requested','user_event', true, 'core'),
    (10022, 'password_reset_completed','user_event', true, 'core'),
    (10030, 'identity_created',       'user_event', true, 'core'),
    (10031, 'identity_updated',       'user_event', true, 'core'),
    (10032, 'identity_deleted',       'user_event', true, 'core'),
    (10033, 'identity_enabled',       'user_event', true, 'core'),
    (10034, 'identity_disabled',      'user_event', true, 'core'),
    (10035, 'identity_verified',     'user_event', true, 'core'),
    (10040, 'email_verified',         'user_event', true, 'core'),
    (10041, 'phone_verified',         'user_event', true, 'core'),
    (10050, 'mfa_enabled',            'user_event', true, 'core'),
    (10051, 'mfa_disabled',           'user_event', true, 'core'),
    -- 10060-10062 removed: invitation events moved to invitation_event category (22001-22012)
    (10070, 'external_data_updated',  'user_event', true, 'core'),
    (10080, 'user_blacklisted',      'user_event', true, 'core'),
    (10081, 'user_unblacklisted',    'user_event', true, 'core'),
    (10082, 'user_creation_blocked', 'user_event', true, 'core'),

    -- Tenant events (11001-11999)
    (11001, 'tenant_created',         'tenant_event', true, 'core'),
    (11002, 'tenant_updated',         'tenant_event', true, 'core'),
    (11003, 'tenant_deleted',         'tenant_event', true, 'core'),
    (11010, 'tenant_user_added',      'tenant_event', true, 'core'),
    (11011, 'tenant_user_removed',    'tenant_event', true, 'core'),

    -- Permission events (12001-12999)
    (12001, 'permission_created',     'permission_event', true, 'core'),
    (12002, 'permission_updated',     'permission_event', true, 'core'),
    (12003, 'permission_deleted',     'permission_event', true, 'core'),
    (12010, 'permission_assigned',    'permission_event', true, 'core'),
    (12011, 'permission_revoked',     'permission_event', true, 'core'),
    (12020, 'perm_set_created',       'permission_event', true, 'core'),
    (12021, 'perm_set_updated',       'permission_event', true, 'core'),
    (12022, 'perm_set_deleted',       'permission_event', true, 'core'),
    (12023, 'perm_set_assigned',      'permission_event', true, 'core'),
    (12024, 'perm_set_revoked',       'permission_event', true, 'core'),

    -- Group events (13001-13999)
    (13001, 'group_created',          'group_event', true, 'core'),
    (13002, 'group_updated',          'group_event', true, 'core'),
    (13003, 'group_deleted',          'group_event', true, 'core'),
    (13010, 'group_member_added',     'group_event', true, 'core'),
    (13011, 'group_member_removed',   'group_event', true, 'core'),
    (13020, 'group_mapping_created',  'group_event', true, 'core'),
    (13021, 'group_mapping_deleted',  'group_event', true, 'core'),
    (13030, 'group_members_synced',  'group_event', true, 'core'),

    -- API key events (14001-14999)
    (14001, 'apikey_created',         'apikey_event', true, 'core'),
    (14002, 'apikey_updated',         'apikey_event', true, 'core'),
    (14003, 'apikey_deleted',         'apikey_event', true, 'core'),
    (14010, 'apikey_validated',       'apikey_event', true, 'core'),
    (14011, 'apikey_validation_failed','apikey_event', true, 'core'),

    -- Token events (15001-15999)
    (15001, 'token_created',          'token_event', true, 'core'),
    (15002, 'token_used',             'token_event', true, 'core'),
    (15003, 'token_expired',          'token_event', true, 'core'),
    (15004, 'token_failed',           'token_event', true, 'core'),

    -- Provider events (16001-16999)
    (16001, 'provider_created',       'provider_event', true, 'core'),
    (16002, 'provider_updated',       'provider_event', true, 'core'),
    (16003, 'provider_deleted',       'provider_event', true, 'core'),
    (16004, 'provider_enabled',       'provider_event', true, 'core'),
    (16005, 'provider_disabled',      'provider_event', true, 'core'),

    -- Maintenance events (17001-17999)
    (17001, 'audit_data_purged',      'maintenance_event', true, 'core'),

    -- Resource access events (18001-18999)
    (18001, 'resource_type_created',       'resource_event', true, 'core'),
    (18002, 'resource_type_updated',       'resource_event', true, 'core'),
    (18010, 'resource_access_granted',     'resource_event', true, 'core'),
    (18011, 'resource_access_revoked',     'resource_event', true, 'core'),
    (18012, 'resource_access_denied',      'resource_event', true, 'core'),
    (18013, 'resource_access_bulk_revoked','resource_event', true, 'core'),

    -- Token config events (19001-19999)
    (19001, 'token_type_created',     'token_config_event', true, 'core'),
    (19002, 'token_type_updated',     'token_config_event', true, 'core'),
    (19003, 'token_type_deleted',     'token_config_event', true, 'core')
ON CONFLICT DO NOTHING;

/*
 * Event Codes - Errors (30xxx)
 */
INSERT INTO const.event_code (event_id, code, category_code, is_system, source) VALUES
    -- Security/auth errors (30001-30999)
    (30001, 'err_api_key_invalid',    'security_error', true, 'core'),
    (30002, 'err_token_invalid',      'security_error', true, 'core'),
    (30003, 'err_token_wrong_user',   'security_error', true, 'core'),
    (30004, 'err_token_already_used', 'security_error', true, 'core'),
    (30005, 'err_token_not_found',    'security_error', true, 'core'),

    -- Validation errors (31001-31999)
    (31001, 'err_either_group_or_user',      'validation_error', true, 'core'),
    (31002, 'err_either_perm_set_or_perm',   'validation_error', true, 'core'),
    (31003, 'err_either_perm_id_or_code',    'validation_error', true, 'core'),
    (31004, 'err_either_mapping_id_or_role', 'validation_error', true, 'core'),
    (31010, 'err_event_code_is_system',      'validation_error', true, 'core'),
    (31011, 'err_event_code_not_found',      'validation_error', true, 'core'),
    (31012, 'err_event_category_not_empty',  'validation_error', true, 'core'),
    (31013, 'err_event_id_out_of_range',     'validation_error', true, 'core'),
    (31014, 'err_event_category_not_found',  'validation_error', true, 'core'),

    -- Permission errors (32001-32999)
    (32001, 'err_no_permission',             'permission_error', true, 'core'),
    (32002, 'err_permission_not_found',      'permission_error', true, 'core'),
    (32003, 'err_permission_not_assignable', 'permission_error', true, 'core'),
    (32004, 'err_perm_set_not_found',        'permission_error', true, 'core'),
    (32005, 'err_perm_set_not_assignable',   'permission_error', true, 'core'),
    (32006, 'err_perm_set_wrong_tenant',     'permission_error', true, 'core'),
    (32007, 'err_parent_permission_not_found','permission_error', true, 'core'),
    (32008, 'err_some_perms_not_assignable', 'permission_error', true, 'core'),

    -- User/group errors (33001-33999)
    (33001, 'err_user_not_found',            'user_error', true, 'core'),
    (33002, 'err_user_is_system',            'user_error', true, 'core'),
    (33003, 'err_user_not_active',           'user_error', true, 'core'),
    (33004, 'err_user_locked',               'user_error', true, 'core'),
    (33005, 'err_user_cannot_login',         'user_error', true, 'core'),
    (33006, 'err_user_no_email_provider',    'user_error', true, 'core'),
    (33007, 'err_identity_already_used',     'user_error', true, 'core'),
    (33008, 'err_identity_not_active',       'user_error', true, 'core'),
    (33009, 'err_identity_not_found',        'user_error', true, 'core'),
    (33010, 'err_provider_not_active',       'user_error', true, 'core'),
    (33011, 'err_group_not_found',           'user_error', true, 'core'),
    (33012, 'err_group_not_active',          'user_error', true, 'core'),
    (33013, 'err_group_not_assignable',      'user_error', true, 'core'),
    (33014, 'err_group_is_system',           'user_error', true, 'core'),
    (33015, 'err_not_owner',                 'user_error', true, 'core'),
    (33018, 'err_user_blacklisted',          'user_error', true, 'core'),
    (33019, 'err_identity_blacklisted',      'user_error', true, 'core'),

    -- Tenant errors (34001-34999)
    (34001, 'err_no_tenant_access',          'tenant_error', true, 'core'),
    (34002, 'err_cross_tenant_requires_admin', 'tenant_error', true, 'core'),

    -- Resource access errors (35001-35999)
    (35001, 'err_no_resource_access',             'resource_error', true, 'core'),
    (35002, 'err_resource_grant_no_target',       'resource_error', true, 'core'),
    (35003, 'err_resource_type_not_found',        'resource_error', true, 'core'),
    (35004, 'err_resource_access_flag_not_found', 'resource_error', true, 'core'),
    (35005, 'err_resource_id_invalid',             'resource_error', true, 'core'),
    (35006, 'err_resource_flag_not_valid',         'resource_error', true, 'core'),

    -- Token config errors (36001-36999)
    (36001, 'err_token_type_not_found',      'token_config_error', true, 'core'),
    (36002, 'err_token_type_is_system',      'token_config_error', true, 'core')
ON CONFLICT DO NOTHING;

/*
 * Event Message Templates
 * =======================
 *
 * Message templates for journal entries. Use {placeholder} syntax for values
 * that will be filled from data_payload at display time.
 *
 * Common placeholders:
 * - {actor} - User who performed the action (from created_by)
 * - {username}, {email} - Target user info
 * - {group_title}, {tenant_title} - Entity names
 * - {permission_code}, {perm_set_code} - Permission identifiers
 */
INSERT INTO const.event_message (event_id, language_code, message_template) VALUES
    -- User events (10001-10999)
    (10001, 'en', 'User "{username}" was created by {actor}'),
    (10002, 'en', 'User "{username}" was updated by {actor}'),
    (10003, 'en', 'User "{username}" was deleted by {actor}'),
    (10004, 'en', 'User "{username}" was enabled by {actor}'),
    (10005, 'en', 'User "{username}" was disabled by {actor}'),
    (10006, 'en', 'User "{username}" was locked by {actor}'),
    (10007, 'en', 'User "{username}" was unlocked by {actor}'),
    (10008, 'en', 'User "{username}" registered via {provider}'),
    (10010, 'en', 'User "{username}" logged in'),
    (10011, 'en', 'User "{username}" logged out'),
    (10012, 'en', 'Login failed for "{username}": {reason}'),
    (10020, 'en', 'Password was changed for user "{username}" by {actor}'),
    (10021, 'en', 'Password reset was requested for user "{username}"'),
    (10022, 'en', 'Password reset was completed for user "{username}"'),
    (10030, 'en', 'Identity "{provider_code}" was created for user "{username}" by {actor}'),
    (10031, 'en', 'Identity "{provider_code}" was updated for user "{username}" by {actor}'),
    (10032, 'en', 'Identity "{provider_code}" was deleted for user "{username}" by {actor}'),
    (10033, 'en', 'Identity "{provider_code}" was enabled for user "{username}" by {actor}'),
    (10034, 'en', 'Identity "{provider_code}" was disabled for user "{username}" by {actor}'),
    (10035, 'en', 'Identity "{provider_code}" was verified for user "{username}" by {actor}'),
    (10040, 'en', 'Email was verified for user "{username}"'),
    (10041, 'en', 'Phone was verified for user "{username}"'),
    (10050, 'en', 'MFA was enabled for user "{username}" by {actor}'),
    (10051, 'en', 'MFA was disabled for user "{username}" by {actor}'),
    -- 10060-10062 removed: invitation events moved to invitation_event category (22001-22012)
    (10070, 'en', 'User "{username}" data was updated from external source'),
    (10080, 'en', 'User "{username}" was added to blacklist by {actor}: {reason}'),
    (10081, 'en', 'User "{username}" was removed from blacklist by {actor}'),
    (10082, 'en', 'User creation was blocked by blacklist: {username} {provider_code} {provider_uid}'),

    -- Tenant events (11001-11999)
    (11001, 'en', 'Tenant "{tenant_title}" was created by {actor}'),
    (11002, 'en', 'Tenant "{tenant_title}" was updated by {actor}'),
    (11003, 'en', 'Tenant "{tenant_title}" was deleted by {actor}'),
    (11010, 'en', 'User "{username}" was added to tenant "{tenant_title}" by {actor}'),
    (11011, 'en', 'User "{username}" was removed from tenant "{tenant_title}" by {actor}'),

    -- Permission events (12001-12999)
    (12001, 'en', 'Permission "{permission_code}" was created by {actor}'),
    (12002, 'en', 'Permission "{permission_code}" was updated by {actor}'),
    (12003, 'en', 'Permission "{permission_code}" was deleted by {actor}'),
    (12010, 'en', 'Permission "{permission_code}" was assigned to {target_type} "{target_name}" by {actor}'),
    (12011, 'en', 'Permission "{permission_code}" was revoked from {target_type} "{target_name}" by {actor}'),
    (12020, 'en', 'Permission set "{perm_set_code}" was created in tenant "{tenant_title}" by {actor}'),
    (12021, 'en', 'Permission set "{perm_set_code}" was updated by {actor}'),
    (12022, 'en', 'Permission set "{perm_set_code}" was deleted by {actor}'),
    (12023, 'en', 'Permission set "{perm_set_code}" was assigned to {target_type} "{target_name}" by {actor}'),
    (12024, 'en', 'Permission set "{perm_set_code}" was revoked from {target_type} "{target_name}" by {actor}'),

    -- Group events (13001-13999)
    (13001, 'en', 'Group "{group_title}" was created in tenant "{tenant_title}" by {actor}'),
    (13002, 'en', 'Group "{group_title}" was updated by {actor}'),
    (13003, 'en', 'Group "{group_title}" was deleted by {actor}'),
    (13010, 'en', 'User "{username}" was added to group "{group_title}" by {actor}'),
    (13011, 'en', 'User "{username}" was removed from group "{group_title}" by {actor}'),
    (13020, 'en', 'Mapping "{mapping_name}" was created for group "{group_title}" by {actor}'),
    (13021, 'en', 'Mapping "{mapping_name}" was deleted from group "{group_title}" by {actor}'),
    (13030, 'en', 'Group members synchronized: {members_created} created, {members_deleted} deleted for group via mapping {user_group_mapping_id}'),

    -- API key events (14001-14999)
    (14001, 'en', 'API key "{api_key_title}" was created by {actor}'),
    (14002, 'en', 'API key "{api_key_title}" was updated by {actor}'),
    (14003, 'en', 'API key "{api_key_title}" was deleted by {actor}'),
    (14010, 'en', 'API key "{api_key_title}" was validated'),
    (14011, 'en', 'API key validation failed: {reason}'),

    -- Token events (15001-15999)
    (15001, 'en', 'Token was created for user "{username}"'),
    (15002, 'en', 'Token was used by user "{username}"'),
    (15003, 'en', 'Token expired for user "{username}"'),
    (15004, 'en', 'Token validation failed for user "{username}": {reason}'),

    -- Provider events (16001-16999)
    (16001, 'en', 'Provider "{provider_code}" was created by {actor}'),
    (16002, 'en', 'Provider "{provider_code}" was updated by {actor}'),
    (16003, 'en', 'Provider "{provider_code}" was deleted by {actor}'),
    (16004, 'en', 'Provider "{provider_code}" was enabled by {actor}'),
    (16005, 'en', 'Provider "{provider_code}" was disabled by {actor}'),

    -- Maintenance events (17001-17999)
    (17001, 'en', 'Audit data purged by {actor}: {journal_deleted} journal entries and {user_events_deleted} user events removed'),

    -- Token config events (19001-19999)
    (19001, 'en', 'Token type "{token_type_code}" was created by {actor}'),
    (19002, 'en', 'Token type "{token_type_code}" was updated by {actor}'),
    (19003, 'en', 'Token type "{token_type_code}" was deleted by {actor}'),

    -- Resource access events (18xxx)
    (18001, 'en', 'Resource type "{resource_type}" was created by {actor}'),
    (18002, 'en', 'Resource type "{resource_type}" was updated by {actor}'),
    (18010, 'en', 'Access to {resource_type} "{resource_id}" was granted to {target_type} "{target_name}" by {actor}'),
    (18011, 'en', 'Access to {resource_type} "{resource_id}" was revoked from {target_type} "{target_name}" by {actor}'),
    (18012, 'en', 'Deny rule on {resource_type} "{resource_id}" was set for user "{target_name}" by {actor}'),
    (18013, 'en', 'All access to {resource_type} "{resource_id}" was revoked by {actor}'),

    -- Resource access error messages (35xxx)
    (35001, 'en', 'User (uid: {user_id}) has no access to resource (type: {resource_type}, id: {resource_id})'),
    (35002, 'en', 'Either target user_id or user_group_id must be provided'),
    (35003, 'en', 'Resource type "{resource_type}" does not exist or is not active'),
    (35004, 'en', 'Access flag "{access_flag}" does not exist'),
    (35005, 'en', 'Resource ID is missing required key "{key}" for resource type "{resource_type}"'),
    (35006, 'en', 'Access flag "{access_flag}" is not valid for resource type "{resource_type}"'),

    -- Token config error messages (36xxx)
    (36001, 'en', 'Token type "{token_type_code}" does not exist'),
    (36002, 'en', 'Token type "{token_type_code}" is a system token type and cannot be modified or deleted'),

    -- Validation error messages (31xxx)
    (31010, 'en', 'Cannot modify or delete system event code (event_id: {event_id})'),
    (31011, 'en', 'Event code (event_id: {event_id}) does not exist'),
    (31012, 'en', 'Event category "{category_code}" still has event codes and cannot be deleted'),
    (31013, 'en', 'Event ID {event_id} is outside the allowed range ({range_start}-{range_end}) for category "{category_code}"'),
    (31014, 'en', 'Event category "{category_code}" does not exist'),

    -- Blacklist error messages (33018-33019)
    (33018, 'en', 'User (username: {username}) is blacklisted and cannot be created'),
    (33019, 'en', 'User identity (provider: {provider_code}, uid: {provider_uid}) is blacklisted and cannot be created')
ON CONFLICT DO NOTHING;

-- Create system user, primary tenant, and seed all permissions/providers/groups
SELECT * FROM unsecure.create_user_system();
SELECT * FROM unsecure.create_primary_tenant();

-- Create service accounts (IDs 2-6, reserved range 1-999)
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_registrator', 'Registrator', null, 1);
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_authenticator', 'Authenticator', null, 2);
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_token_manager', 'Token Manager', null, 3);
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_api_gateway', 'API Gateway', null, 4);
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_group_syncer', 'Group Syncer', null, 5);
SELECT * FROM unsecure.create_service_user_info('initial_script', 1, null, 'svc_data_processor', 'Data Processor', null, 799);

-- Mark service accounts as system users that cannot login
UPDATE auth.user_info SET is_system = true WHERE user_id = 1;
UPDATE auth.user_info SET is_system = true, can_login = false WHERE user_id IN (2, 3, 4, 5, 6, 800);

-- Reset sequence to 1000 to reserve space for system users
ALTER SEQUENCE auth.user_info_user_id_seq RESTART WITH 1000;

-- Permissions, providers, groups, and perm set seeding moved to 047_seed_permissions.sql
-- (requires public.translation which is created in 030)

-- Sequence resets and permission backfill moved to 047_seed_permissions.sql
