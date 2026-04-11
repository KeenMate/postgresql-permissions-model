/*
 * Drop Inline Title/Description Columns
 * =======================================
 *
 * Moves display text from inline columns to public.translation (context-aware).
 * Affected tables:
 *   - const.resource_type:       title, full_title, description → translations
 *   - const.resource_access_flag: title → translations
 *   - const.resource_role:        title, description → translations
 *
 * All replaced functions gain _language_code parameter (default 'en').
 * Translations use data_group = table name, data_object_code = entity code,
 * context = 'title' | 'description'.
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

-- ============================================================================
-- 2. Helper: recompute full_title translations for a type and descendants
-- ============================================================================
-- Mirrors the old unsecure.update_resource_type_full_title but writes to
-- public.translation with context='full_title' instead of a column.
-- Called after any title translation is created/updated.
--
create or replace function unsecure.update_resource_type_full_title_translations(
    _path           ext.ltree,
    _language_code  text default 'en',
    _created_by     text default 'system'
) returns void
    language plpgsql
as
$$
declare
    _rt record;
    _full_title text;
begin
    for _rt in
        select code, path
        from const.resource_type
        where path <@ _path
        order by path
    loop
        -- Build breadcrumb from ancestor title translations
        select array_to_string(
            array(
                select coalesce(t.value, a.code)
                from const.resource_type a
                left join public.translation t
                    on t.data_group = 'resource_type' and t.data_object_code = a.code
                    and t.context = 'title' and t.language_code = _language_code
                where a.path @> _rt.path
                order by a.path
            ), ' > ')
        into _full_title;

        -- Upsert full_title translation
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', _rt.code, 'full_title', _full_title)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end loop;

    -- Refresh MV so reads see updated full_titles
    perform unsecure.refresh_translation_cache();
end;
$$;

-- ============================================================================
-- 5. Drop old function signatures to avoid ambiguous overloads
-- ============================================================================
-- resource type functions (from 035)
drop function if exists auth.create_resource_type(text, bigint, text, text, text, text, text, integer, text, jsonb, text[]);
drop function if exists auth.update_resource_type(text, bigint, text, text, text, text, boolean, text, integer);
drop function if exists auth.ensure_resource_types(text, bigint, text, jsonb, text, integer);
drop function if exists auth.get_resource_types(text, text, boolean);
-- access flag functions (from 035)
drop function if exists auth.ensure_access_flags(text, bigint, text, jsonb, text, integer);
drop function if exists auth.get_access_flags(text);
-- resource role functions (from 044)
drop function if exists auth.create_resource_role(text, bigint, text, text, text, text, text, text[], text, integer);
drop function if exists auth.ensure_resource_roles(text, bigint, text, jsonb, text, boolean, integer);
drop function if exists auth.update_resource_role(text, bigint, text, text, text, text, boolean, text, integer);
drop function if exists auth.get_resource_roles(text, text, boolean);
drop function if exists auth.get_resource_role_assignments(bigint, text, text, jsonb, integer);

-- ============================================================================
-- 5. Replaced functions — resource type management
-- ============================================================================

-- auth.create_resource_type
create or replace function auth.create_resource_type(
    _created_by   text,
    _user_id      bigint,
    _correlation_id text,
    _code         text,
    _title        text,
    _parent_code  text default null,
    _description  text default null,
    _tenant_id    integer default 1,
    _source       text default null,
    _key_schema   jsonb default '{}'::jsonb,
    _access_flags text[] default null,
    _language_code text default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __parent_code  text,
    __path         ext.ltree,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    _path ext.ltree;
    _flag text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if _parent_code is not null then
        if not exists (
            select 1 from const.resource_type where code = _parent_code and is_active = true
        ) then
            perform error.raise_35003(_parent_code);
        end if;
    end if;

    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
    end if;

    _path := text2ltree(_code);

    insert into const.resource_type (code, source, parent_code, path, key_schema)
    values (_code, _source, _parent_code, _path, coalesce(_key_schema, '{}'::jsonb))
    on conflict do nothing;

    -- Translations for title + description
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', _code, 'title', _title)
        on conflict do nothing;
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_type', _code, 'description', _description)
        on conflict do nothing;
    end if;

    -- Recompute full_title for this type and all descendants
    perform unsecure.update_resource_type_full_title_translations(_path, _language_code, _created_by);

    if _access_flags is not null then
        foreach _flag in array _access_flags
        loop
            insert into const.resource_type_flag (resource_type_code, access_flag_code)
            values (_code, _flag) on conflict do nothing;
        end loop;
    end if;

    perform unsecure.ensure_resource_access_partition(_code);

    return query
        select rt.code,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.parent_code, rt.path, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt where rt.code = _code;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18001, 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title,
            'parent_code', _parent_code, 'key_schema', _key_schema, 'access_flags', _access_flags)
        , _tenant_id);
end;
$$;

-- auth.update_resource_type
create or replace function auth.update_resource_type(
    _updated_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _title          text    default null,
    _description    text    default null,
    _is_active      boolean default null,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __parent_code  text,
    __path         ext.ltree,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    _path ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if not exists (select 1 from const.resource_type where code = _code) then
        perform error.raise_35003(_code);
    end if;

    select path from const.resource_type where code = _code into _path;

    update const.resource_type
    set is_active = coalesce(_is_active, is_active),
        source    = coalesce(_source, source)
    where code = _code;

    -- Upsert translations
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_type', _code, 'title', _title)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();

        -- Recompute full_title for this type and all descendants
        perform unsecure.update_resource_type_full_title_translations(_path, _language_code, _updated_by);
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_type', _code, 'description', _description)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;

    return query
        select rt.code,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.parent_code, rt.path, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt where rt.code = _code;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18002, 'resource_type', 0
        , jsonb_build_object('resource_type', _code, 'title', _title, 'is_active', _is_active)
        , _tenant_id);
end;
$$;

-- auth.ensure_resource_types
create or replace function auth.ensure_resource_types(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _resource_types jsonb,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __parent_code  text,
    __path         ext.ltree,
    __key_schema   jsonb,
    __access_flags text[]
)
    language plpgsql
as
$$
declare
    _item          jsonb;
    _code          text;
    _title         text;
    _parent_code   text;
    _description   text;
    _item_source   text;
    _key_schema    jsonb;
    _access_flags  text[];
    _flag          text;
    _path          ext.ltree;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for _item in
        select value from jsonb_array_elements(_resource_types)
        order by nlevel(text2ltree(value->>'code'))
    loop
        _code        := _item->>'code';
        _title       := _item->>'title';
        _parent_code := _item->>'parent_code';
        _description := _item->>'description';
        _item_source := coalesce(_item->>'source', _source);
        _key_schema  := coalesce(_item->'key_schema', '{}'::jsonb);
        _path        := text2ltree(_code);

        if _item ? 'access_flags' and _item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(_item->'access_flags') as f(value)
            into _access_flags;
        else
            _access_flags := null;
        end if;

        if not exists (select 1 from const.resource_type where code = _code) then
            if _parent_code is not null then
                if not exists (select 1 from const.resource_type where code = _parent_code and is_active = true) then
                    perform error.raise_35003(_parent_code);
                end if;
            end if;

            if _access_flags is not null then
                perform unsecure.validate_access_flags(_access_flags);
            end if;

            insert into const.resource_type (code, source, parent_code, path, key_schema)
            values (_code, _item_source, _parent_code, _path, _key_schema)
            on conflict do nothing;
        end if;

        -- Translations (upsert)
        if _title is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_type', _code, 'title', _title)
            on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;
        if _description is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_type', _code, 'description', _description)
            on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;

        -- Recompute full_title for this type and all descendants
        perform unsecure.update_resource_type_full_title_translations(_path, _language_code, _created_by);

        if _access_flags is not null then
            foreach _flag in array _access_flags
            loop
                insert into const.resource_type_flag (resource_type_code, access_flag_code)
                values (_code, _flag) on conflict do nothing;
            end loop;
        end if;

        perform unsecure.ensure_resource_access_partition(_code);

        perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18001, 'resource_type', 0
            , jsonb_build_object('resource_type', _code, 'title', _title,
                'parent_code', _parent_code, 'key_schema', _key_schema, 'access_flags', _access_flags)
            , _tenant_id);
    end loop;

    return query
        select rt.code,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'full_title' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_type' and mv.data_object_code = rt.code and mv.language_code = _language_code),
               rt.is_active, rt.source, rt.parent_code, rt.path, rt.key_schema,
               (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
                from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
        from const.resource_type rt
        where rt.code in (select value->>'code' from jsonb_array_elements(_resource_types))
        order by rt.path;
end;
$$;

-- auth.get_resource_types
create or replace function auth.get_resource_types(
    _source        text    default null,
    _parent_code   text    default null,
    _active_only   boolean default true,
    _language_code text    default 'en'
) returns table(
    __code         text,
    __title        text,
    __full_title   text,
    __description  text,
    __is_active    boolean,
    __source       text,
    __parent_code  text,
    __path         ext.ltree,
    __key_schema   jsonb,
    __access_flags text[]
)
    stable
    language plpgsql
as
$$
begin
    return query
    select rt.code,
           mv.values->>'title',
           mv.values->>'full_title',
           mv.values->>'description',
           rt.is_active, rt.source, rt.parent_code, rt.path, rt.key_schema,
           (select array_agg(rtf.access_flag_code order by rtf.access_flag_code)
            from const.resource_type_flag rtf where rtf.resource_type_code = rt.code)
    from const.resource_type rt
    left join public.mv_translation mv
        on mv.data_group = 'resource_type' and mv.data_object_code = rt.code
        and mv.language_code = _language_code
    where (_active_only = false or rt.is_active = true)
      and (_source is null or rt.source = _source)
      and (_parent_code is null or rt.parent_code = _parent_code)
    order by rt.path;
end;
$$;

-- ============================================================================
-- 5. Replaced functions — access flag management
-- ============================================================================

-- auth.ensure_access_flags
create or replace function auth.ensure_access_flags(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _flags          jsonb,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(__code text, __title text, __source text)
    language plpgsql
as
$$
declare
    _item jsonb;
    _code text;
    _title text;
    _item_source text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for _item in select value from jsonb_array_elements(_flags)
    loop
        _code        := _item->>'code';
        _title       := _item->>'title';
        _item_source := coalesce(_item->>'source', _source);

        if _code is null or _title is null then
            raise exception 'Access flag requires both "code" and "title" fields'
                using errcode = '35004';
        end if;

        insert into const.resource_access_flag (code, source)
        values (_code, _item_source)
        on conflict do nothing;

        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_access_flag', _code, 'title', _title)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end loop;

    perform unsecure.refresh_translation_cache();

    return query
    select f.code,
           (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_access_flag' and mv.data_object_code = f.code and mv.language_code = _language_code),
           f.source
    from const.resource_access_flag f
    where f.code in (select value->>'code' from jsonb_array_elements(_flags))
    order by f.code;
end;
$$;

-- auth.get_access_flags
create or replace function auth.get_access_flags(
    _source        text default null,
    _language_code text default 'en'
) returns table(__code text, __title text, __source text)
    stable
    language plpgsql
as
$$
begin
    return query
    select f.code,
           mv.values->>'title',
           f.source
    from const.resource_access_flag f
    left join public.mv_translation mv
        on mv.data_group = 'resource_access_flag' and mv.data_object_code = f.code
        and mv.language_code = _language_code
    where (_source is null or f.source = _source)
    order by f.code;
end;
$$;

-- ============================================================================
-- 6. Replaced functions — resource role management
-- ============================================================================

-- auth.create_resource_role
create or replace function auth.create_resource_role(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _resource_type  text,
    _title          text,
    _description    text    default null,
    _access_flags   text[]  default null,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
declare
    _flag text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);
    perform unsecure.validate_resource_type(_resource_type);

    if _access_flags is not null then
        perform unsecure.validate_access_flags(_access_flags);
        perform unsecure.validate_role_flags_for_type(_code, _resource_type, _access_flags);
    end if;

    insert into const.resource_role (code, resource_type, source)
    values (_code, _resource_type, _source)
    on conflict do nothing;

    -- Translations
    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_role', _code, 'title', _title)
        on conflict do nothing;
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_created_by, _created_by, _language_code, 'resource_role', _code, 'description', _description)
        on conflict do nothing;
    end if;

    if _access_flags is not null then
        foreach _flag in array _access_flags
        loop
            insert into const.resource_role_flag (resource_role_code, access_flag_code)
            values (_code, _flag) on conflict do nothing;
        end loop;
    end if;

    perform unsecure.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r where r.code = _code;

    perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
        , 18003, 'resource_role', 0
        , jsonb_build_object('role_code', _code, 'resource_type', _resource_type,
            'title', _title, 'access_flags', _access_flags, 'source', _source)
        , _tenant_id);
end;
$$;

-- auth.ensure_resource_roles
create or replace function auth.ensure_resource_roles(
    _created_by     text,
    _user_id        bigint,
    _correlation_id text,
    _roles          jsonb,
    _source         text    default null,
    _is_final_state boolean default false,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
declare
    _item          jsonb;
    _code          text;
    _res_type      text;
    _title         text;
    _desc          text;
    _item_source   text;
    _access_flags  text[];
    _flag          text;
    _existing_code text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    for _item in select value from jsonb_array_elements(_roles)
    loop
        _code       := _item->>'code';
        _res_type   := _item->>'resource_type';
        _title      := _item->>'title';
        _desc       := _item->>'description';
        _item_source := coalesce(_item->>'source', _source);

        if _item ? 'access_flags' and _item->'access_flags' is not null then
            select array_agg(f.value::text)
            from jsonb_array_elements_text(_item->'access_flags') as f(value)
            into _access_flags;
        else
            _access_flags := null;
        end if;

        perform unsecure.validate_resource_type(_res_type);

        if _access_flags is not null then
            perform unsecure.validate_access_flags(_access_flags);
            perform unsecure.validate_role_flags_for_type(_code, _res_type, _access_flags);
        end if;

        if exists (select 1 from const.resource_role where code = _code) then
            update const.resource_role
            set source    = coalesce(_item_source, source),
                is_active = true
            where code = _code;
        else
            insert into const.resource_role (code, resource_type, source)
            values (_code, _res_type, _item_source);
        end if;

        -- Translations (upsert)
        if _title is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', _code, 'title', _title)
            on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;
        if _desc is not null then
            insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
            values (_created_by, _created_by, _language_code, 'resource_role', _code, 'description', _desc)
            on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
                where data_object_code is not null
            do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
        end if;

        if _access_flags is not null then
            delete from const.resource_role_flag
            where resource_role_code = _code and access_flag_code != all(_access_flags);
            foreach _flag in array _access_flags
            loop
                insert into const.resource_role_flag (resource_role_code, access_flag_code)
                values (_code, _flag) on conflict do nothing;
            end loop;
        end if;

        perform create_journal_message_for_entity(_created_by, _user_id, _correlation_id
            , 18003, 'resource_role', 0
            , jsonb_build_object('role_code', _code, 'resource_type', _res_type,
                'title', _title, 'access_flags', _access_flags)
            , _tenant_id);
    end loop;

    if _is_final_state and _source is not null then
        for _existing_code in
            select r.code from const.resource_role r
            where r.source = _source and r.is_active = true
              and r.code not in (select value->>'code' from jsonb_array_elements(_roles))
        loop
            update const.resource_role set is_active = false where code = _existing_code;
        end loop;
    end if;

    perform unsecure.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r
        where r.code in (select value->>'code' from jsonb_array_elements(_roles))
        order by r.resource_type, r.code;
end;
$$;

-- auth.update_resource_role
create or replace function auth.update_resource_role(
    _updated_by     text,
    _user_id        bigint,
    _correlation_id text,
    _code           text,
    _title          text    default null,
    _description    text    default null,
    _is_active      boolean default null,
    _source         text    default null,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    language plpgsql
as
$$
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.create_resource_type', _tenant_id);

    if not exists (select 1 from const.resource_role where code = _code) then
        perform error.raise_35007(_code);
    end if;

    update const.resource_role
    set is_active = coalesce(_is_active, is_active),
        source    = coalesce(_source, source)
    where code = _code;

    if _title is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_role', _code, 'title', _title)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;
    if _description is not null then
        insert into public.translation (created_by, updated_by, language_code, data_group, data_object_code, context, value)
        values (_updated_by, _updated_by, _language_code, 'resource_role', _code, 'description', _description)
        on conflict (language_code, data_group, data_object_code, coalesce(context, ''))
            where data_object_code is not null
        do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
    end if;

    perform unsecure.refresh_translation_cache();

    return query
        select r.code, r.resource_type,
               (select mv.values->>'title' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               (select mv.values->>'description' from public.mv_translation mv where mv.data_group = 'resource_role' and mv.data_object_code = r.code and mv.language_code = _language_code),
               r.is_active, r.source,
               (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
                from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
        from const.resource_role r where r.code = _code;

    perform create_journal_message_for_entity(_updated_by, _user_id, _correlation_id
        , 18004, 'resource_role', 0
        , jsonb_build_object('role_code', _code, 'title', _title, 'is_active', _is_active)
        , _tenant_id);
end;
$$;

-- auth.get_resource_roles
create or replace function auth.get_resource_roles(
    _source        text    default null,
    _resource_type text    default null,
    _active_only   boolean default true,
    _language_code text    default 'en'
) returns table(
    __code          text,
    __resource_type text,
    __title         text,
    __description   text,
    __is_active     boolean,
    __source        text,
    __access_flags  text[]
)
    stable
    language plpgsql
as
$$
begin
    return query
    select r.code, r.resource_type,
           mv.values->>'title',
           mv.values->>'description',
           r.is_active, r.source,
           (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
            from const.resource_role_flag rrf where rrf.resource_role_code = r.code)
    from const.resource_role r
    left join public.mv_translation mv
        on mv.data_group = 'resource_role' and mv.data_object_code = r.code
        and mv.language_code = _language_code
    where (_active_only = false or r.is_active = true)
      and (_source is null or r.source = _source)
      and (_resource_type is null or r.resource_type = _resource_type)
    order by r.resource_type, r.code;
end;
$$;

-- auth.get_resource_role_assignments
create or replace function auth.get_resource_role_assignments(
    _user_id        bigint,
    _correlation_id text,
    _resource_type  text,
    _resource_id    jsonb,
    _tenant_id      integer default 1,
    _language_code  text    default 'en'
) returns table(
    __resource_role_assignment_id bigint,
    __user_id            bigint,
    __user_display_name  text,
    __user_group_id      integer,
    __group_title        text,
    __role_code          text,
    __role_title         text,
    __access_flags       text[],
    __granted_by         bigint,
    __granted_by_name    text,
    __created_at         timestamptz
)
    stable
    language plpgsql
as
$$
declare
    _root_type text;
begin
    perform auth.has_permission(_user_id, _correlation_id, 'resources.get_grants', _tenant_id);

    _root_type := split_part(_resource_type, '.', 1);

    return query
    select
        rra.resource_role_assignment_id,
        rra.user_id,
        ui.display_name,
        rra.user_group_id,
        ug.title,
        rra.role_code,
        mv_role.values->>'title',
        (select array_agg(rrf.access_flag_code order by rrf.access_flag_code)
         from const.resource_role_flag rrf where rrf.resource_role_code = rra.role_code),
        rra.granted_by,
        gb.display_name,
        rra.created_at
    from auth.resource_role_assignment rra
    left join auth.user_info ui on ui.user_id = rra.user_id
    left join auth.user_group ug on ug.user_group_id = rra.user_group_id
    left join public.mv_translation mv_role
        on mv_role.data_group = 'resource_role' and mv_role.data_object_code = rra.role_code
        and mv_role.language_code = _language_code
    left join auth.user_info gb on gb.user_id = rra.granted_by
    where rra.root_type = _root_type
      and rra.resource_type = _resource_type
      and rra.tenant_id = _tenant_id
      and rra.resource_id = _resource_id
    order by rra.role_code, rra.created_at;
end;
$$;

-- ============================================================================
-- Final: refresh MV after all seed translations
-- ============================================================================
select unsecure.refresh_translation_cache();
