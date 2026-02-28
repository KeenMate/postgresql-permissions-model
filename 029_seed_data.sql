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
INSERT INTO const.event_category (category_code, title, range_start, range_end, is_error, source) VALUES
    -- Informational events (10xxx)
    ('user_event',       'User Events',       10001, 10999, false, 'core'),
    ('tenant_event',     'Tenant Events',     11001, 11999, false, 'core'),
    ('permission_event', 'Permission Events', 12001, 12999, false, 'core'),
    ('group_event',      'Group Events',      13001, 13999, false, 'core'),
    ('apikey_event',     'API Key Events',    14001, 14999, false, 'core'),
    ('token_event',      'Token Events',      15001, 15999, false, 'core'),
    ('provider_event',   'Provider Events',   16001, 16999, false, 'core'),
    ('maintenance_event','Maintenance Events', 17001, 17999, false, 'core'),
    ('resource_event',    'Resource Access Events', 18001, 18999, false, 'core'),
    ('token_config_event','Token Config Events',19001, 19999, false, 'core'),
    -- Errors (30xxx)
    ('security_error',   'Security Errors',   30001, 30999, true, 'core'),
    ('validation_error', 'Validation Errors', 31001, 31999, true, 'core'),
    ('permission_error', 'Permission Errors', 32001, 32999, true, 'core'),
    ('user_error',       'User/Group Errors', 33001, 33999, true, 'core'),
    ('tenant_error',     'Tenant Errors',     34001, 34999, true, 'core'),
    ('resource_error',    'Resource Access Errors', 35001, 35999, true, 'core'),
    ('token_config_error','Token Config Errors',36001, 36999, true, 'core')
ON CONFLICT DO NOTHING;

/*
 * Event Codes - Informational Events (10xxx)
 */
INSERT INTO const.event_code (event_id, code, category_code, title, description, is_system, source) VALUES
    -- User events (10001-10999)
    (10001, 'user_created',           'user_event', 'User Created',           'New user account was created', true, 'core'),
    (10002, 'user_updated',           'user_event', 'User Updated',           'User account was updated', true, 'core'),
    (10003, 'user_deleted',           'user_event', 'User Deleted',           'User account was deleted', true, 'core'),
    (10004, 'user_enabled',           'user_event', 'User Enabled',           'User account was enabled', true, 'core'),
    (10005, 'user_disabled',          'user_event', 'User Disabled',          'User account was disabled', true, 'core'),
    (10006, 'user_locked',            'user_event', 'User Locked',            'User account was locked', true, 'core'),
    (10007, 'user_unlocked',          'user_event', 'User Unlocked',          'User account was unlocked', true, 'core'),
    (10008, 'user_registered',        'user_event', 'User Registered',        'User successfully registered a new account', true, 'core'),
    (10010, 'user_logged_in',         'user_event', 'User Logged In',         'User successfully logged in', true, 'core'),
    (10011, 'user_logged_out',        'user_event', 'User Logged Out',        'User logged out', true, 'core'),
    (10012, 'user_login_failed',      'user_event', 'User Login Failed',      'User login attempt failed', true, 'core'),
    (10020, 'password_changed',       'user_event', 'Password Changed',       'User password was changed', true, 'core'),
    (10021, 'password_reset_requested','user_event','Password Reset Requested','Password reset was requested', true, 'core'),
    (10022, 'password_reset_completed','user_event','Password Reset Completed','Password reset was completed', true, 'core'),
    (10030, 'identity_created',       'user_event', 'Identity Created',       'User identity was created', true, 'core'),
    (10031, 'identity_updated',       'user_event', 'Identity Updated',       'User identity was updated', true, 'core'),
    (10032, 'identity_deleted',       'user_event', 'Identity Deleted',       'User identity was deleted', true, 'core'),
    (10033, 'identity_enabled',       'user_event', 'Identity Enabled',       'User identity was enabled', true, 'core'),
    (10034, 'identity_disabled',      'user_event', 'Identity Disabled',      'User identity was disabled', true, 'core'),
    (10040, 'email_verified',         'user_event', 'Email Verified',         'User email was verified', true, 'core'),
    (10041, 'phone_verified',         'user_event', 'Phone Verified',         'User phone was verified', true, 'core'),
    (10050, 'mfa_enabled',            'user_event', 'MFA Enabled',            'Multi-factor authentication was enabled', true, 'core'),
    (10051, 'mfa_disabled',           'user_event', 'MFA Disabled',           'Multi-factor authentication was disabled', true, 'core'),
    (10060, 'invitation_sent',        'user_event', 'Invitation Sent',        'User invitation was sent', true, 'core'),
    (10061, 'invitation_accepted',    'user_event', 'Invitation Accepted',    'User invitation was accepted', true, 'core'),
    (10062, 'invitation_rejected',    'user_event', 'Invitation Rejected',    'User invitation was rejected', true, 'core'),
    (10070, 'external_data_updated',  'user_event', 'External Data Updated',  'User data was updated from external source', true, 'core'),

    -- Tenant events (11001-11999)
    (11001, 'tenant_created',         'tenant_event', 'Tenant Created',       'New tenant was created', true, 'core'),
    (11002, 'tenant_updated',         'tenant_event', 'Tenant Updated',       'Tenant was updated', true, 'core'),
    (11003, 'tenant_deleted',         'tenant_event', 'Tenant Deleted',       'Tenant was deleted', true, 'core'),
    (11010, 'tenant_user_added',      'tenant_event', 'User Added to Tenant', 'User was added to tenant', true, 'core'),
    (11011, 'tenant_user_removed',    'tenant_event', 'User Removed from Tenant', 'User was removed from tenant', true, 'core'),

    -- Permission events (12001-12999)
    (12001, 'permission_created',     'permission_event', 'Permission Created',     'New permission was created', true, 'core'),
    (12002, 'permission_updated',     'permission_event', 'Permission Updated',     'Permission was updated', true, 'core'),
    (12003, 'permission_deleted',     'permission_event', 'Permission Deleted',     'Permission was deleted', true, 'core'),
    (12010, 'permission_assigned',    'permission_event', 'Permission Assigned',    'Permission was assigned', true, 'core'),
    (12011, 'permission_revoked',     'permission_event', 'Permission Revoked',     'Permission was revoked', true, 'core'),
    (12020, 'perm_set_created',       'permission_event', 'Permission Set Created', 'New permission set was created', true, 'core'),
    (12021, 'perm_set_updated',       'permission_event', 'Permission Set Updated', 'Permission set was updated', true, 'core'),
    (12022, 'perm_set_deleted',       'permission_event', 'Permission Set Deleted', 'Permission set was deleted', true, 'core'),
    (12023, 'perm_set_assigned',      'permission_event', 'Permission Set Assigned','Permission set was assigned', true, 'core'),
    (12024, 'perm_set_revoked',       'permission_event', 'Permission Set Revoked', 'Permission set was revoked', true, 'core'),

    -- Group events (13001-13999)
    (13001, 'group_created',          'group_event', 'Group Created',        'New group was created', true, 'core'),
    (13002, 'group_updated',          'group_event', 'Group Updated',        'Group was updated', true, 'core'),
    (13003, 'group_deleted',          'group_event', 'Group Deleted',        'Group was deleted', true, 'core'),
    (13010, 'group_member_added',     'group_event', 'Member Added',         'Member was added to group', true, 'core'),
    (13011, 'group_member_removed',   'group_event', 'Member Removed',       'Member was removed from group', true, 'core'),
    (13020, 'group_mapping_created',  'group_event', 'Mapping Created',      'Group mapping was created', true, 'core'),
    (13021, 'group_mapping_deleted',  'group_event', 'Mapping Deleted',      'Group mapping was deleted', true, 'core'),
    (13030, 'group_members_synced',  'group_event', 'Group Members Synced', 'External group members synchronized from provider', true, 'core'),

    -- API key events (14001-14999)
    (14001, 'apikey_created',         'apikey_event', 'API Key Created',     'New API key was created', true, 'core'),
    (14002, 'apikey_updated',         'apikey_event', 'API Key Updated',     'API key was updated', true, 'core'),
    (14003, 'apikey_deleted',         'apikey_event', 'API Key Deleted',     'API key was deleted', true, 'core'),
    (14010, 'apikey_validated',       'apikey_event', 'API Key Validated',   'API key was validated', true, 'core'),
    (14011, 'apikey_validation_failed','apikey_event','API Key Validation Failed', 'API key validation failed', true, 'core'),

    -- Token events (15001-15999)
    (15001, 'token_created',          'token_event', 'Token Created',        'New token was created', true, 'core'),
    (15002, 'token_used',             'token_event', 'Token Used',           'Token was used', true, 'core'),
    (15003, 'token_expired',          'token_event', 'Token Expired',        'Token expired', true, 'core'),
    (15004, 'token_failed',           'token_event', 'Token Failed',         'Token validation failed', true, 'core'),

    -- Provider events (16001-16999)
    (16001, 'provider_created',       'provider_event', 'Provider Created',  'New provider was created', true, 'core'),
    (16002, 'provider_updated',       'provider_event', 'Provider Updated',  'Provider was updated', true, 'core'),
    (16003, 'provider_deleted',       'provider_event', 'Provider Deleted',  'Provider was deleted', true, 'core'),
    (16004, 'provider_enabled',       'provider_event', 'Provider Enabled',  'Provider was enabled', true, 'core'),
    (16005, 'provider_disabled',      'provider_event', 'Provider Disabled', 'Provider was disabled', true, 'core'),

    -- Maintenance events (17001-17999)
    (17001, 'audit_data_purged',      'maintenance_event', 'Audit Data Purged',  'Old audit data was purged', true, 'core'),

    -- Resource access events (18001-18999)
    (18001, 'resource_type_created',       'resource_event', 'Resource Type Created',       'New resource type was registered', true, 'core'),
    (18010, 'resource_access_granted',     'resource_event', 'Resource Access Granted',     'Access was granted to a resource', true, 'core'),
    (18011, 'resource_access_revoked',     'resource_event', 'Resource Access Revoked',     'Access was revoked from a resource', true, 'core'),
    (18012, 'resource_access_denied',      'resource_event', 'Resource Access Denied',      'Deny rule was set on a resource', true, 'core'),
    (18013, 'resource_access_bulk_revoked','resource_event', 'Resource Access Bulk Revoked','All access was revoked from a resource', true, 'core'),

    -- Token config events (19001-19999)
    (19001, 'token_type_created',     'token_config_event', 'Token Type Created', 'New token type was created', true, 'core'),
    (19002, 'token_type_updated',     'token_config_event', 'Token Type Updated', 'Token type was updated', true, 'core'),
    (19003, 'token_type_deleted',     'token_config_event', 'Token Type Deleted', 'Token type was deleted', true, 'core')
ON CONFLICT DO NOTHING;

/*
 * Event Codes - Errors (30xxx)
 */
INSERT INTO const.event_code (event_id, code, category_code, title, description, is_system, source) VALUES
    -- Security/auth errors (30001-30999)
    (30001, 'err_api_key_invalid',    'security_error', 'Invalid API Key',       'API key/secret combination is not valid', true, 'core'),
    (30002, 'err_token_invalid',      'security_error', 'Invalid Token',         'Token is not valid or has expired', true, 'core'),
    (30003, 'err_token_wrong_user',   'security_error', 'Token Wrong User',      'Token was created for different user', true, 'core'),
    (30004, 'err_token_already_used', 'security_error', 'Token Already Used',    'Token has already been used', true, 'core'),
    (30005, 'err_token_not_found',    'security_error', 'Token Not Found',       'Token does not exist', true, 'core'),

    -- Validation errors (31001-31999)
    (31001, 'err_either_group_or_user',      'validation_error', 'Either Group or User Required',      'Either user group or target user id must not be null', true, 'core'),
    (31002, 'err_either_perm_set_or_perm',   'validation_error', 'Either Perm Set or Perm Required',   'Either permission set code or permission code must not be null', true, 'core'),
    (31003, 'err_either_perm_id_or_code',    'validation_error', 'Either Perm ID or Code Required',    'Either permission id or code must not be null', true, 'core'),
    (31004, 'err_either_mapping_id_or_role', 'validation_error', 'Either Mapping ID or Role Required', 'Either mapped object id or mapped role must not be empty', true, 'core'),
    (31010, 'err_event_code_is_system',      'validation_error', 'System Event Code',                  'Cannot modify or delete a system event code', true, 'core'),
    (31011, 'err_event_code_not_found',      'validation_error', 'Event Code Not Found',               'Event code does not exist', true, 'core'),
    (31012, 'err_event_category_not_empty',  'validation_error', 'Event Category Not Empty',           'Event category still has event codes', true, 'core'),
    (31013, 'err_event_id_out_of_range',     'validation_error', 'Event ID Out of Range',              'Event ID is outside the category range', true, 'core'),
    (31014, 'err_event_category_not_found',  'validation_error', 'Event Category Not Found',           'Event category does not exist', true, 'core'),

    -- Permission errors (32001-32999)
    (32001, 'err_no_permission',             'permission_error', 'No Permission',             'User does not have required permission', true, 'core'),
    (32002, 'err_permission_not_found',      'permission_error', 'Permission Not Found',      'Permission does not exist', true, 'core'),
    (32003, 'err_permission_not_assignable', 'permission_error', 'Permission Not Assignable', 'Permission is not assignable', true, 'core'),
    (32004, 'err_perm_set_not_found',        'permission_error', 'Permission Set Not Found',  'Permission set does not exist', true, 'core'),
    (32005, 'err_perm_set_not_assignable',   'permission_error', 'Permission Set Not Assignable', 'Permission set is not assignable', true, 'core'),
    (32006, 'err_perm_set_wrong_tenant',     'permission_error', 'Permission Set Wrong Tenant', 'Permission set is not defined in this tenant', true, 'core'),
    (32007, 'err_parent_permission_not_found','permission_error','Parent Permission Not Found', 'Parent permission does not exist', true, 'core'),
    (32008, 'err_some_perms_not_assignable', 'permission_error', 'Some Permissions Not Assignable', 'Some permissions are not assignable', true, 'core'),

    -- User/group errors (33001-33999)
    (33001, 'err_user_not_found',            'user_error', 'User Not Found',         'User does not exist', true, 'core'),
    (33002, 'err_user_is_system',            'user_error', 'User Is System',         'User is a system user', true, 'core'),
    (33003, 'err_user_not_active',           'user_error', 'User Not Active',        'User is not in active state', true, 'core'),
    (33004, 'err_user_locked',               'user_error', 'User Locked',            'User is locked out', true, 'core'),
    (33005, 'err_user_cannot_login',         'user_error', 'User Cannot Login',      'User is not supposed to log in', true, 'core'),
    (33006, 'err_user_no_email_provider',    'user_error', 'User No Email Provider', 'User cannot be ensured for email provider', true, 'core'),
    (33007, 'err_identity_already_used',     'user_error', 'Identity Already Used',  'User identity is already in use', true, 'core'),
    (33008, 'err_identity_not_active',       'user_error', 'Identity Not Active',    'User identity is not in active state', true, 'core'),
    (33009, 'err_identity_not_found',        'user_error', 'Identity Not Found',     'User identity does not exist', true, 'core'),
    (33010, 'err_provider_not_active',       'user_error', 'Provider Not Active',    'Provider is not in active state', true, 'core'),
    (33011, 'err_group_not_found',           'user_error', 'Group Not Found',        'User group does not exist', true, 'core'),
    (33012, 'err_group_not_active',          'user_error', 'Group Not Active',       'User group is not active', true, 'core'),
    (33013, 'err_group_not_assignable',      'user_error', 'Group Not Assignable',   'User group is not assignable or is external', true, 'core'),
    (33014, 'err_group_is_system',           'user_error', 'Group Is System',        'User group is a system group', true, 'core'),
    (33015, 'err_not_owner',                 'user_error', 'Not Owner',              'User is not tenant or group owner', true, 'core'),

    -- Tenant errors (34001-34999)
    (34001, 'err_no_tenant_access',          'tenant_error', 'No Tenant Access',     'User has no access to this tenant', true, 'core'),

    -- Resource access errors (35001-35999)
    (35001, 'err_no_resource_access',             'resource_error', 'No Resource Access',             'User has no access to this resource', true, 'core'),
    (35002, 'err_resource_grant_no_target',       'resource_error', 'No Grant Target',                'Either target user or group must be specified', true, 'core'),
    (35003, 'err_resource_type_not_found',        'resource_error', 'Resource Type Not Found',        'Resource type does not exist or is inactive', true, 'core'),
    (35004, 'err_resource_access_flag_not_found', 'resource_error', 'Access Flag Not Found',          'Access flag does not exist', true, 'core'),

    -- Token config errors (36001-36999)
    (36001, 'err_token_type_not_found',      'token_config_error', 'Token Type Not Found', 'Token type does not exist', true, 'core'),
    (36002, 'err_token_type_is_system',      'token_config_error', 'Token Type Is System', 'Cannot modify or delete a system token type', true, 'core')
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
    (10040, 'en', 'Email was verified for user "{username}"'),
    (10041, 'en', 'Phone was verified for user "{username}"'),
    (10050, 'en', 'MFA was enabled for user "{username}" by {actor}'),
    (10051, 'en', 'MFA was disabled for user "{username}" by {actor}'),
    (10060, 'en', 'Invitation was sent to "{email}" by {actor}'),
    (10061, 'en', 'Invitation was accepted by "{username}"'),
    (10062, 'en', 'Invitation was rejected by "{email}"'),
    (10070, 'en', 'User "{username}" data was updated from external source'),

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
    (18010, 'en', 'Access to {resource_type} "{resource_id}" was granted to {target_type} "{target_name}" by {actor}'),
    (18011, 'en', 'Access to {resource_type} "{resource_id}" was revoked from {target_type} "{target_name}" by {actor}'),
    (18012, 'en', 'Deny rule on {resource_type} "{resource_id}" was set for user "{target_name}" by {actor}'),
    (18013, 'en', 'All access to {resource_type} "{resource_id}" was revoked by {actor}'),

    -- Resource access error messages (35xxx)
    (35001, 'en', 'User (uid: {user_id}) has no access to resource (type: {resource_type}, id: {resource_id})'),
    (35002, 'en', 'Either target user_id or user_group_id must be provided'),
    (35003, 'en', 'Resource type "{resource_type}" does not exist or is not active'),
    (35004, 'en', 'Access flag "{access_flag}" does not exist'),

    -- Token config error messages (36xxx)
    (36001, 'en', 'Token type "{token_type_code}" does not exist'),
    (36002, 'en', 'Token type "{token_type_code}" is a system token type and cannot be modified or deleted'),

    -- Validation error messages (31xxx)
    (31010, 'en', 'Cannot modify or delete system event code (event_id: {event_id})'),
    (31011, 'en', 'Event code (event_id: {event_id}) does not exist'),
    (31012, 'en', 'Event category "{category_code}" still has event codes and cannot be deleted'),
    (31013, 'en', 'Event ID {event_id} is outside the allowed range ({range_start}-{range_end}) for category "{category_code}"'),
    (31014, 'en', 'Event category "{category_code}" does not exist')
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
UPDATE auth.user_info SET is_system = true, can_login = false WHERE user_id IN (2, 3, 4, 5, 6, 800);

-- Reset sequence to 1000 to reserve space for system users
ALTER SEQUENCE auth.user_info_user_id_seq RESTART WITH 1000;

-- Seed permissions, providers, groups, and perm sets
SELECT auth.seed_permission_data();

-- Assign service permission sets to service accounts
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 2, 'svc_registrator_permissions');
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 3, 'svc_authenticator_permissions');
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 4, 'svc_token_permissions');
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 5, 'svc_api_gateway_permissions');
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 6, 'svc_group_syncer_permissions');
SELECT * FROM unsecure.assign_permission_as_system(null::integer, 800, 'svc_data_processor_permissions');

-- Reset sequences to 1000 to reserve space for system tenants and groups
ALTER SEQUENCE auth.tenant_tenant_id_seq RESTART WITH 1000;
ALTER SEQUENCE auth.user_group_user_group_id_seq RESTART WITH 1000;

-- Backfill short_code for all permissions (in case any were created without it)
UPDATE auth.permission SET short_code = unsecure.compute_short_code(permission_id)
WHERE short_code IS NULL;
