/*
 * Seed Translations for Core Data
 * =================================
 *
 * Title/description translations for const tables (event_category, event_code,
 * resource_access_flag). Must run after 030 (creates public.translation with
 * context column) and 045 (translation functions).
 *
 * This file is part of the PostgreSQL Permissions Model v3
 */

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

-- ============================================================================
-- 1. Seed translations for core data
-- ============================================================================

-- Core access flag translations
insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    ('system', 'system', 'en', 'resource_access_flag', 'read',    'title', 'Read'),
    ('system', 'system', 'en', 'resource_access_flag', 'write',   'title', 'Write'),
    ('system', 'system', 'en', 'resource_access_flag', 'delete',  'title', 'Delete'),
    ('system', 'system', 'en', 'resource_access_flag', 'share',   'title', 'Share'),
    ('system', 'system', 'en', 'resource_access_flag', 'approve', 'title', 'Approve'),
    ('system', 'system', 'en', 'resource_access_flag', 'export',  'title', 'Export')
on conflict do nothing;

-- Event category translations (from 029 seed data)
insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    ('system', 'system', 'en', 'event_category', 'user_event',        'title', 'User Events'),
    ('system', 'system', 'en', 'event_category', 'tenant_event',      'title', 'Tenant Events'),
    ('system', 'system', 'en', 'event_category', 'permission_event',  'title', 'Permission Events'),
    ('system', 'system', 'en', 'event_category', 'group_event',       'title', 'Group Events'),
    ('system', 'system', 'en', 'event_category', 'apikey_event',      'title', 'API Key Events'),
    ('system', 'system', 'en', 'event_category', 'token_event',       'title', 'Token Events'),
    ('system', 'system', 'en', 'event_category', 'provider_event',    'title', 'Provider Events'),
    ('system', 'system', 'en', 'event_category', 'maintenance_event', 'title', 'Maintenance Events'),
    ('system', 'system', 'en', 'event_category', 'resource_event',    'title', 'Resource Access Events'),
    ('system', 'system', 'en', 'event_category', 'token_config_event','title', 'Token Config Events'),
    ('system', 'system', 'en', 'event_category', 'security_error',    'title', 'Security Errors'),
    ('system', 'system', 'en', 'event_category', 'validation_error',  'title', 'Validation Errors'),
    ('system', 'system', 'en', 'event_category', 'permission_error',  'title', 'Permission Errors'),
    ('system', 'system', 'en', 'event_category', 'user_error',        'title', 'User/Group Errors'),
    ('system', 'system', 'en', 'event_category', 'tenant_error',      'title', 'Tenant Errors'),
    ('system', 'system', 'en', 'event_category', 'resource_error',    'title', 'Resource Access Errors'),
    ('system', 'system', 'en', 'event_category', 'token_config_error','title', 'Token Config Errors')
on conflict do nothing;

-- Event code translations (titles + descriptions from 029 seed data)
insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value) values
    -- User events (10001-10999)
    ('system', 'system', 'en', 'event_code', 'user_created',            'title', 'User Created'),
    ('system', 'system', 'en', 'event_code', 'user_created',            'description', 'New user account was created'),
    ('system', 'system', 'en', 'event_code', 'user_updated',            'title', 'User Updated'),
    ('system', 'system', 'en', 'event_code', 'user_updated',            'description', 'User account was updated'),
    ('system', 'system', 'en', 'event_code', 'user_deleted',            'title', 'User Deleted'),
    ('system', 'system', 'en', 'event_code', 'user_deleted',            'description', 'User account was deleted'),
    ('system', 'system', 'en', 'event_code', 'user_enabled',            'title', 'User Enabled'),
    ('system', 'system', 'en', 'event_code', 'user_enabled',            'description', 'User account was enabled'),
    ('system', 'system', 'en', 'event_code', 'user_disabled',           'title', 'User Disabled'),
    ('system', 'system', 'en', 'event_code', 'user_disabled',           'description', 'User account was disabled'),
    ('system', 'system', 'en', 'event_code', 'user_locked',             'title', 'User Locked'),
    ('system', 'system', 'en', 'event_code', 'user_locked',             'description', 'User account was locked'),
    ('system', 'system', 'en', 'event_code', 'user_unlocked',           'title', 'User Unlocked'),
    ('system', 'system', 'en', 'event_code', 'user_unlocked',           'description', 'User account was unlocked'),
    ('system', 'system', 'en', 'event_code', 'user_registered',         'title', 'User Registered'),
    ('system', 'system', 'en', 'event_code', 'user_registered',         'description', 'User successfully registered a new account'),
    ('system', 'system', 'en', 'event_code', 'user_logged_in',          'title', 'User Logged In'),
    ('system', 'system', 'en', 'event_code', 'user_logged_in',          'description', 'User successfully logged in'),
    ('system', 'system', 'en', 'event_code', 'user_logged_out',         'title', 'User Logged Out'),
    ('system', 'system', 'en', 'event_code', 'user_logged_out',         'description', 'User logged out'),
    ('system', 'system', 'en', 'event_code', 'user_login_failed',       'title', 'User Login Failed'),
    ('system', 'system', 'en', 'event_code', 'user_login_failed',       'description', 'User login attempt failed'),
    ('system', 'system', 'en', 'event_code', 'password_changed',        'title', 'Password Changed'),
    ('system', 'system', 'en', 'event_code', 'password_changed',        'description', 'User password was changed'),
    ('system', 'system', 'en', 'event_code', 'password_reset_requested','title', 'Password Reset Requested'),
    ('system', 'system', 'en', 'event_code', 'password_reset_requested','description', 'Password reset was requested'),
    ('system', 'system', 'en', 'event_code', 'password_reset_completed','title', 'Password Reset Completed'),
    ('system', 'system', 'en', 'event_code', 'password_reset_completed','description', 'Password reset was completed'),
    ('system', 'system', 'en', 'event_code', 'identity_created',        'title', 'Identity Created'),
    ('system', 'system', 'en', 'event_code', 'identity_created',        'description', 'User identity was created'),
    ('system', 'system', 'en', 'event_code', 'identity_updated',        'title', 'Identity Updated'),
    ('system', 'system', 'en', 'event_code', 'identity_updated',        'description', 'User identity was updated'),
    ('system', 'system', 'en', 'event_code', 'identity_deleted',        'title', 'Identity Deleted'),
    ('system', 'system', 'en', 'event_code', 'identity_deleted',        'description', 'User identity was deleted'),
    ('system', 'system', 'en', 'event_code', 'identity_enabled',        'title', 'Identity Enabled'),
    ('system', 'system', 'en', 'event_code', 'identity_enabled',        'description', 'User identity was enabled'),
    ('system', 'system', 'en', 'event_code', 'identity_disabled',       'title', 'Identity Disabled'),
    ('system', 'system', 'en', 'event_code', 'identity_disabled',       'description', 'User identity was disabled'),
    ('system', 'system', 'en', 'event_code', 'identity_verified',       'title', 'Identity Verified'),
    ('system', 'system', 'en', 'event_code', 'identity_verified',       'description', 'User identity was marked as verified'),
    ('system', 'system', 'en', 'event_code', 'email_verified',          'title', 'Email Verified'),
    ('system', 'system', 'en', 'event_code', 'email_verified',          'description', 'User email was verified'),
    ('system', 'system', 'en', 'event_code', 'phone_verified',          'title', 'Phone Verified'),
    ('system', 'system', 'en', 'event_code', 'phone_verified',          'description', 'User phone was verified'),
    ('system', 'system', 'en', 'event_code', 'mfa_enabled',             'title', 'MFA Enabled'),
    ('system', 'system', 'en', 'event_code', 'mfa_enabled',             'description', 'Multi-factor authentication was enabled'),
    ('system', 'system', 'en', 'event_code', 'mfa_disabled',            'title', 'MFA Disabled'),
    ('system', 'system', 'en', 'event_code', 'mfa_disabled',            'description', 'Multi-factor authentication was disabled'),
    ('system', 'system', 'en', 'event_code', 'external_data_updated',   'title', 'External Data Updated'),
    ('system', 'system', 'en', 'event_code', 'external_data_updated',   'description', 'User data was updated from external source'),
    ('system', 'system', 'en', 'event_code', 'user_blacklisted',        'title', 'User Blacklisted'),
    ('system', 'system', 'en', 'event_code', 'user_blacklisted',        'description', 'User was added to blacklist'),
    ('system', 'system', 'en', 'event_code', 'user_unblacklisted',      'title', 'User Unblacklisted'),
    ('system', 'system', 'en', 'event_code', 'user_unblacklisted',      'description', 'User was removed from blacklist'),
    ('system', 'system', 'en', 'event_code', 'user_creation_blocked',   'title', 'User Creation Blocked'),
    ('system', 'system', 'en', 'event_code', 'user_creation_blocked',   'description', 'User creation was blocked by blacklist'),

    -- Tenant events (11001-11999)
    ('system', 'system', 'en', 'event_code', 'tenant_created',          'title', 'Tenant Created'),
    ('system', 'system', 'en', 'event_code', 'tenant_created',          'description', 'New tenant was created'),
    ('system', 'system', 'en', 'event_code', 'tenant_updated',          'title', 'Tenant Updated'),
    ('system', 'system', 'en', 'event_code', 'tenant_updated',          'description', 'Tenant was updated'),
    ('system', 'system', 'en', 'event_code', 'tenant_deleted',          'title', 'Tenant Deleted'),
    ('system', 'system', 'en', 'event_code', 'tenant_deleted',          'description', 'Tenant was deleted'),
    ('system', 'system', 'en', 'event_code', 'tenant_user_added',       'title', 'User Added to Tenant'),
    ('system', 'system', 'en', 'event_code', 'tenant_user_added',       'description', 'User was added to tenant'),
    ('system', 'system', 'en', 'event_code', 'tenant_user_removed',     'title', 'User Removed from Tenant'),
    ('system', 'system', 'en', 'event_code', 'tenant_user_removed',     'description', 'User was removed from tenant'),

    -- Permission events (12001-12999)
    ('system', 'system', 'en', 'event_code', 'permission_created',      'title', 'Permission Created'),
    ('system', 'system', 'en', 'event_code', 'permission_created',      'description', 'New permission was created'),
    ('system', 'system', 'en', 'event_code', 'permission_updated',      'title', 'Permission Updated'),
    ('system', 'system', 'en', 'event_code', 'permission_updated',      'description', 'Permission was updated'),
    ('system', 'system', 'en', 'event_code', 'permission_deleted',      'title', 'Permission Deleted'),
    ('system', 'system', 'en', 'event_code', 'permission_deleted',      'description', 'Permission was deleted'),
    ('system', 'system', 'en', 'event_code', 'permission_assigned',     'title', 'Permission Assigned'),
    ('system', 'system', 'en', 'event_code', 'permission_assigned',     'description', 'Permission was assigned'),
    ('system', 'system', 'en', 'event_code', 'permission_revoked',      'title', 'Permission Revoked'),
    ('system', 'system', 'en', 'event_code', 'permission_revoked',      'description', 'Permission was revoked'),
    ('system', 'system', 'en', 'event_code', 'perm_set_created',        'title', 'Permission Set Created'),
    ('system', 'system', 'en', 'event_code', 'perm_set_created',        'description', 'New permission set was created'),
    ('system', 'system', 'en', 'event_code', 'perm_set_updated',        'title', 'Permission Set Updated'),
    ('system', 'system', 'en', 'event_code', 'perm_set_updated',        'description', 'Permission set was updated'),
    ('system', 'system', 'en', 'event_code', 'perm_set_deleted',        'title', 'Permission Set Deleted'),
    ('system', 'system', 'en', 'event_code', 'perm_set_deleted',        'description', 'Permission set was deleted'),
    ('system', 'system', 'en', 'event_code', 'perm_set_assigned',       'title', 'Permission Set Assigned'),
    ('system', 'system', 'en', 'event_code', 'perm_set_assigned',       'description', 'Permission set was assigned'),
    ('system', 'system', 'en', 'event_code', 'perm_set_revoked',        'title', 'Permission Set Revoked'),
    ('system', 'system', 'en', 'event_code', 'perm_set_revoked',        'description', 'Permission set was revoked'),

    -- Group events (13001-13999)
    ('system', 'system', 'en', 'event_code', 'group_created',           'title', 'Group Created'),
    ('system', 'system', 'en', 'event_code', 'group_created',           'description', 'New group was created'),
    ('system', 'system', 'en', 'event_code', 'group_updated',           'title', 'Group Updated'),
    ('system', 'system', 'en', 'event_code', 'group_updated',           'description', 'Group was updated'),
    ('system', 'system', 'en', 'event_code', 'group_deleted',           'title', 'Group Deleted'),
    ('system', 'system', 'en', 'event_code', 'group_deleted',           'description', 'Group was deleted'),
    ('system', 'system', 'en', 'event_code', 'group_member_added',      'title', 'Member Added'),
    ('system', 'system', 'en', 'event_code', 'group_member_added',      'description', 'Member was added to group'),
    ('system', 'system', 'en', 'event_code', 'group_member_removed',    'title', 'Member Removed'),
    ('system', 'system', 'en', 'event_code', 'group_member_removed',    'description', 'Member was removed from group'),
    ('system', 'system', 'en', 'event_code', 'group_mapping_created',   'title', 'Mapping Created'),
    ('system', 'system', 'en', 'event_code', 'group_mapping_created',   'description', 'Group mapping was created'),
    ('system', 'system', 'en', 'event_code', 'group_mapping_deleted',   'title', 'Mapping Deleted'),
    ('system', 'system', 'en', 'event_code', 'group_mapping_deleted',   'description', 'Group mapping was deleted'),
    ('system', 'system', 'en', 'event_code', 'group_members_synced',    'title', 'Group Members Synced'),
    ('system', 'system', 'en', 'event_code', 'group_members_synced',    'description', 'External group members synchronized from provider'),

    -- API key events (14001-14999)
    ('system', 'system', 'en', 'event_code', 'apikey_created',          'title', 'API Key Created'),
    ('system', 'system', 'en', 'event_code', 'apikey_created',          'description', 'New API key was created'),
    ('system', 'system', 'en', 'event_code', 'apikey_updated',          'title', 'API Key Updated'),
    ('system', 'system', 'en', 'event_code', 'apikey_updated',          'description', 'API key was updated'),
    ('system', 'system', 'en', 'event_code', 'apikey_deleted',          'title', 'API Key Deleted'),
    ('system', 'system', 'en', 'event_code', 'apikey_deleted',          'description', 'API key was deleted'),
    ('system', 'system', 'en', 'event_code', 'apikey_validated',        'title', 'API Key Validated'),
    ('system', 'system', 'en', 'event_code', 'apikey_validated',        'description', 'API key was validated'),
    ('system', 'system', 'en', 'event_code', 'apikey_validation_failed','title', 'API Key Validation Failed'),
    ('system', 'system', 'en', 'event_code', 'apikey_validation_failed','description', 'API key validation failed'),

    -- Token events (15001-15999)
    ('system', 'system', 'en', 'event_code', 'token_created',           'title', 'Token Created'),
    ('system', 'system', 'en', 'event_code', 'token_created',           'description', 'New token was created'),
    ('system', 'system', 'en', 'event_code', 'token_used',              'title', 'Token Used'),
    ('system', 'system', 'en', 'event_code', 'token_used',              'description', 'Token was used'),
    ('system', 'system', 'en', 'event_code', 'token_expired',           'title', 'Token Expired'),
    ('system', 'system', 'en', 'event_code', 'token_expired',           'description', 'Token expired'),
    ('system', 'system', 'en', 'event_code', 'token_failed',            'title', 'Token Failed'),
    ('system', 'system', 'en', 'event_code', 'token_failed',            'description', 'Token validation failed'),

    -- Provider events (16001-16999)
    ('system', 'system', 'en', 'event_code', 'provider_created',        'title', 'Provider Created'),
    ('system', 'system', 'en', 'event_code', 'provider_created',        'description', 'New provider was created'),
    ('system', 'system', 'en', 'event_code', 'provider_updated',        'title', 'Provider Updated'),
    ('system', 'system', 'en', 'event_code', 'provider_updated',        'description', 'Provider was updated'),
    ('system', 'system', 'en', 'event_code', 'provider_deleted',        'title', 'Provider Deleted'),
    ('system', 'system', 'en', 'event_code', 'provider_deleted',        'description', 'Provider was deleted'),
    ('system', 'system', 'en', 'event_code', 'provider_enabled',        'title', 'Provider Enabled'),
    ('system', 'system', 'en', 'event_code', 'provider_enabled',        'description', 'Provider was enabled'),
    ('system', 'system', 'en', 'event_code', 'provider_disabled',       'title', 'Provider Disabled'),
    ('system', 'system', 'en', 'event_code', 'provider_disabled',       'description', 'Provider was disabled'),

    -- Maintenance events (17001-17999)
    ('system', 'system', 'en', 'event_code', 'audit_data_purged',       'title', 'Audit Data Purged'),
    ('system', 'system', 'en', 'event_code', 'audit_data_purged',       'description', 'Old audit data was purged'),

    -- Resource access events (18001-18999)
    ('system', 'system', 'en', 'event_code', 'resource_type_created',        'title', 'Resource Type Created'),
    ('system', 'system', 'en', 'event_code', 'resource_type_created',        'description', 'New resource type was registered'),
    ('system', 'system', 'en', 'event_code', 'resource_type_updated',        'title', 'Resource Type Updated'),
    ('system', 'system', 'en', 'event_code', 'resource_type_updated',        'description', 'Resource type was updated'),
    ('system', 'system', 'en', 'event_code', 'resource_access_granted',      'title', 'Resource Access Granted'),
    ('system', 'system', 'en', 'event_code', 'resource_access_granted',      'description', 'Access was granted to a resource'),
    ('system', 'system', 'en', 'event_code', 'resource_access_revoked',      'title', 'Resource Access Revoked'),
    ('system', 'system', 'en', 'event_code', 'resource_access_revoked',      'description', 'Access was revoked from a resource'),
    ('system', 'system', 'en', 'event_code', 'resource_access_denied',       'title', 'Resource Access Denied'),
    ('system', 'system', 'en', 'event_code', 'resource_access_denied',       'description', 'Deny rule was set on a resource'),
    ('system', 'system', 'en', 'event_code', 'resource_access_bulk_revoked', 'title', 'Resource Access Bulk Revoked'),
    ('system', 'system', 'en', 'event_code', 'resource_access_bulk_revoked', 'description', 'All access was revoked from a resource'),

    -- Token config events (19001-19999)
    ('system', 'system', 'en', 'event_code', 'token_type_created',      'title', 'Token Type Created'),
    ('system', 'system', 'en', 'event_code', 'token_type_created',      'description', 'New token type was created'),
    ('system', 'system', 'en', 'event_code', 'token_type_updated',      'title', 'Token Type Updated'),
    ('system', 'system', 'en', 'event_code', 'token_type_updated',      'description', 'Token type was updated'),
    ('system', 'system', 'en', 'event_code', 'token_type_deleted',      'title', 'Token Type Deleted'),
    ('system', 'system', 'en', 'event_code', 'token_type_deleted',      'description', 'Token type was deleted'),

    -- Security errors (30001-30999)
    ('system', 'system', 'en', 'event_code', 'err_api_key_invalid',     'title', 'Invalid API Key'),
    ('system', 'system', 'en', 'event_code', 'err_api_key_invalid',     'description', 'API key/secret combination is not valid'),
    ('system', 'system', 'en', 'event_code', 'err_token_invalid',       'title', 'Invalid Token'),
    ('system', 'system', 'en', 'event_code', 'err_token_invalid',       'description', 'Token is not valid or has expired'),
    ('system', 'system', 'en', 'event_code', 'err_token_wrong_user',    'title', 'Token Wrong User'),
    ('system', 'system', 'en', 'event_code', 'err_token_wrong_user',    'description', 'Token was created for different user'),
    ('system', 'system', 'en', 'event_code', 'err_token_already_used',  'title', 'Token Already Used'),
    ('system', 'system', 'en', 'event_code', 'err_token_already_used',  'description', 'Token has already been used'),
    ('system', 'system', 'en', 'event_code', 'err_token_not_found',     'title', 'Token Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_token_not_found',     'description', 'Token does not exist'),

    -- Validation errors (31001-31999)
    ('system', 'system', 'en', 'event_code', 'err_either_group_or_user',      'title', 'Either Group or User Required'),
    ('system', 'system', 'en', 'event_code', 'err_either_group_or_user',      'description', 'Either user group or target user id must not be null'),
    ('system', 'system', 'en', 'event_code', 'err_either_perm_set_or_perm',   'title', 'Either Perm Set or Perm Required'),
    ('system', 'system', 'en', 'event_code', 'err_either_perm_set_or_perm',   'description', 'Either permission set code or permission code must not be null'),
    ('system', 'system', 'en', 'event_code', 'err_either_perm_id_or_code',    'title', 'Either Perm ID or Code Required'),
    ('system', 'system', 'en', 'event_code', 'err_either_perm_id_or_code',    'description', 'Either permission id or code must not be null'),
    ('system', 'system', 'en', 'event_code', 'err_either_mapping_id_or_role', 'title', 'Either Mapping ID or Role Required'),
    ('system', 'system', 'en', 'event_code', 'err_either_mapping_id_or_role', 'description', 'Either mapped object id or mapped role must not be empty'),
    ('system', 'system', 'en', 'event_code', 'err_event_code_is_system',      'title', 'System Event Code'),
    ('system', 'system', 'en', 'event_code', 'err_event_code_is_system',      'description', 'Cannot modify or delete a system event code'),
    ('system', 'system', 'en', 'event_code', 'err_event_code_not_found',      'title', 'Event Code Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_event_code_not_found',      'description', 'Event code does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_event_category_not_empty',  'title', 'Event Category Not Empty'),
    ('system', 'system', 'en', 'event_code', 'err_event_category_not_empty',  'description', 'Event category still has event codes'),
    ('system', 'system', 'en', 'event_code', 'err_event_id_out_of_range',     'title', 'Event ID Out of Range'),
    ('system', 'system', 'en', 'event_code', 'err_event_id_out_of_range',     'description', 'Event ID is outside the category range'),
    ('system', 'system', 'en', 'event_code', 'err_event_category_not_found',  'title', 'Event Category Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_event_category_not_found',  'description', 'Event category does not exist'),

    -- Permission errors (32001-32999)
    ('system', 'system', 'en', 'event_code', 'err_no_permission',              'title', 'No Permission'),
    ('system', 'system', 'en', 'event_code', 'err_no_permission',              'description', 'User does not have required permission'),
    ('system', 'system', 'en', 'event_code', 'err_permission_not_found',       'title', 'Permission Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_permission_not_found',       'description', 'Permission does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_permission_not_assignable',  'title', 'Permission Not Assignable'),
    ('system', 'system', 'en', 'event_code', 'err_permission_not_assignable',  'description', 'Permission is not assignable'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_not_found',         'title', 'Permission Set Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_not_found',         'description', 'Permission set does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_not_assignable',    'title', 'Permission Set Not Assignable'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_not_assignable',    'description', 'Permission set is not assignable'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_wrong_tenant',      'title', 'Permission Set Wrong Tenant'),
    ('system', 'system', 'en', 'event_code', 'err_perm_set_wrong_tenant',      'description', 'Permission set is not defined in this tenant'),
    ('system', 'system', 'en', 'event_code', 'err_parent_permission_not_found','title', 'Parent Permission Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_parent_permission_not_found','description', 'Parent permission does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_some_perms_not_assignable',  'title', 'Some Permissions Not Assignable'),
    ('system', 'system', 'en', 'event_code', 'err_some_perms_not_assignable',  'description', 'Some permissions are not assignable'),

    -- User/group errors (33001-33999)
    ('system', 'system', 'en', 'event_code', 'err_user_not_found',             'title', 'User Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_user_not_found',             'description', 'User does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_user_is_system',             'title', 'User Is System'),
    ('system', 'system', 'en', 'event_code', 'err_user_is_system',             'description', 'User is a system user'),
    ('system', 'system', 'en', 'event_code', 'err_user_not_active',            'title', 'User Not Active'),
    ('system', 'system', 'en', 'event_code', 'err_user_not_active',            'description', 'User is not in active state'),
    ('system', 'system', 'en', 'event_code', 'err_user_locked',                'title', 'User Locked'),
    ('system', 'system', 'en', 'event_code', 'err_user_locked',                'description', 'User is locked out'),
    ('system', 'system', 'en', 'event_code', 'err_user_cannot_login',          'title', 'User Cannot Login'),
    ('system', 'system', 'en', 'event_code', 'err_user_cannot_login',          'description', 'User is not supposed to log in'),
    ('system', 'system', 'en', 'event_code', 'err_user_no_email_provider',     'title', 'User No Email Provider'),
    ('system', 'system', 'en', 'event_code', 'err_user_no_email_provider',     'description', 'User cannot be ensured for email provider'),
    ('system', 'system', 'en', 'event_code', 'err_identity_already_used',      'title', 'Identity Already Used'),
    ('system', 'system', 'en', 'event_code', 'err_identity_already_used',      'description', 'User identity is already in use'),
    ('system', 'system', 'en', 'event_code', 'err_identity_not_active',        'title', 'Identity Not Active'),
    ('system', 'system', 'en', 'event_code', 'err_identity_not_active',        'description', 'User identity is not in active state'),
    ('system', 'system', 'en', 'event_code', 'err_identity_not_found',         'title', 'Identity Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_identity_not_found',         'description', 'User identity does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_provider_not_active',        'title', 'Provider Not Active'),
    ('system', 'system', 'en', 'event_code', 'err_provider_not_active',        'description', 'Provider is not in active state'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_found',            'title', 'Group Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_found',            'description', 'User group does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_active',           'title', 'Group Not Active'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_active',           'description', 'User group is not active'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_assignable',       'title', 'Group Not Assignable'),
    ('system', 'system', 'en', 'event_code', 'err_group_not_assignable',       'description', 'User group is not assignable or is external'),
    ('system', 'system', 'en', 'event_code', 'err_group_is_system',            'title', 'Group Is System'),
    ('system', 'system', 'en', 'event_code', 'err_group_is_system',            'description', 'User group is a system group'),
    ('system', 'system', 'en', 'event_code', 'err_not_owner',                  'title', 'Not Owner'),
    ('system', 'system', 'en', 'event_code', 'err_not_owner',                  'description', 'User is not tenant or group owner'),
    ('system', 'system', 'en', 'event_code', 'err_user_blacklisted',           'title', 'User Blacklisted'),
    ('system', 'system', 'en', 'event_code', 'err_user_blacklisted',           'description', 'User is blacklisted and cannot be created'),
    ('system', 'system', 'en', 'event_code', 'err_identity_blacklisted',       'title', 'Identity Blacklisted'),
    ('system', 'system', 'en', 'event_code', 'err_identity_blacklisted',       'description', 'User identity is blacklisted and cannot be created'),

    -- Tenant errors (34001-34999)
    ('system', 'system', 'en', 'event_code', 'err_no_tenant_access',            'title', 'No Tenant Access'),
    ('system', 'system', 'en', 'event_code', 'err_no_tenant_access',            'description', 'User has no access to this tenant'),
    ('system', 'system', 'en', 'event_code', 'err_cross_tenant_requires_admin', 'title', 'Cross-Tenant Requires Admin'),
    ('system', 'system', 'en', 'event_code', 'err_cross_tenant_requires_admin', 'description', 'Cross-tenant access requires admin tenant'),

    -- Resource access errors (35001-35999)
    ('system', 'system', 'en', 'event_code', 'err_no_resource_access',              'title', 'No Resource Access'),
    ('system', 'system', 'en', 'event_code', 'err_no_resource_access',              'description', 'User has no access to this resource'),
    ('system', 'system', 'en', 'event_code', 'err_resource_grant_no_target',        'title', 'No Grant Target'),
    ('system', 'system', 'en', 'event_code', 'err_resource_grant_no_target',        'description', 'Either target user or group must be specified'),
    ('system', 'system', 'en', 'event_code', 'err_resource_type_not_found',         'title', 'Resource Type Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_resource_type_not_found',         'description', 'Resource type does not exist or is inactive'),
    ('system', 'system', 'en', 'event_code', 'err_resource_access_flag_not_found',  'title', 'Access Flag Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_resource_access_flag_not_found',  'description', 'Access flag does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_resource_id_invalid',             'title', 'Invalid Resource ID'),
    ('system', 'system', 'en', 'event_code', 'err_resource_id_invalid',             'description', 'Resource ID is missing a required key for this resource type'),
    ('system', 'system', 'en', 'event_code', 'err_resource_flag_not_valid',         'title', 'Flag Not Valid For Type'),
    ('system', 'system', 'en', 'event_code', 'err_resource_flag_not_valid',         'description', 'Access flag is not valid for this resource type'),

    -- Token config errors (36001-36999)
    ('system', 'system', 'en', 'event_code', 'err_token_type_not_found',     'title', 'Token Type Not Found'),
    ('system', 'system', 'en', 'event_code', 'err_token_type_not_found',     'description', 'Token type does not exist'),
    ('system', 'system', 'en', 'event_code', 'err_token_type_is_system',     'title', 'Token Type Is System'),
    ('system', 'system', 'en', 'event_code', 'err_token_type_is_system',     'description', 'Cannot modify or delete a system token type')
on conflict do nothing;


-- Refresh MV after all seed translations
select unsecure.refresh_translation_cache();
