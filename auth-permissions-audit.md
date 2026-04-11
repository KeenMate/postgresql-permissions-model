# Auth Function Permission Audit

Complete audit of all `auth.*` functions and their RBAC permission requirements.

Generated: 2026-03-08

## User Functions (`020_functions_auth_user.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.enable_user` | `users.enable_user` |
| `auth.disable_user` | `users.disable_user` |
| `auth.unlock_user` | `users.unlock_user` |
| `auth.lock_user` | `users.lock_user` |
| `auth.verify_user_identity` | `users.verify_user_identity` |
| `auth.enable_user_identity` | `users.enable_user_identity` |
| `auth.disable_user_identity` | `users.disable_user_identity` |
| `auth.create_service_user_info` | `users.create_service_user` |
| `auth.update_user_password` | `users.change_password` (conditional — only when acting on another user) |
| `auth.register_user` | `users.register_user` |
| `auth.add_user_to_default_groups` | `users.add_to_default_groups` |
| `auth.get_user_by_id` | **None** |
| `auth.get_user_identity` | `users.get_user_identity` |
| `auth.get_user_identity_by_email` | `users.get_user_identity` |
| `auth.get_user_by_email_for_authentication` | `authentication.get_data` |
| `auth.ensure_user_info` | **None** |
| `auth.update_user_data` | **None** |
| `auth.get_user_data` | `users.get_data` (conditional) |
| `auth.delete_user_info` | `users.delete_user_info` |
| `auth.ensure_user_from_provider` | **None** |
| `auth.update_user_preferences` | `users.update_user_data` (conditional) |
| `auth.get_user_preferences` | `users.get_data` (conditional) |
| `auth.get_user_by_provider_oid` | **None** |
| `auth.search_users` | `users.read_users` |
| `auth.is_blacklisted` | **None** |
| `auth.add_to_blacklist` | `users.manage_blacklist` |
| `auth.remove_from_blacklist` | `users.manage_blacklist` |
| `auth.search_blacklist` | `users.search_blacklist` |

## Group Functions (`021_functions_auth_group.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.is_group_member` | **None** |
| `auth.can_manage_user_group` | **None** (role-checking utility) |
| `auth.create_user_group` | `groups.create_group` |
| `auth.update_user_group` | `groups.update_group` |
| `auth.enable_user_group` | `groups.update_group` |
| `auth.disable_user_group` | `groups.update_group` |
| `auth.lock_user_group` | `groups.lock_group` |
| `auth.unlock_user_group` | `groups.update_group` |
| `auth.delete_user_group` | `groups.delete_group` |
| `auth.get_user_group_by_id` | `groups.get_group` |
| `auth.get_user_group_members` | `groups.get_members` |
| `auth.create_user_group_member` | `groups.update_group` |
| `auth.delete_user_group_member` | `groups.update_group` |
| `auth.get_user_group_mappings` | `groups.get_mapping` |
| `auth.create_user_group_mapping` | `groups.create_mapping` |
| `auth.delete_user_group_mapping` | `groups.delete_mapping` |
| `auth.create_external_user_group` | `groups.create_mapping` |
| `auth.set_user_group_as_hybrid` | `groups.update_group` |
| `auth.set_user_group_as_external` | `groups.update_group` |
| `auth.set_user_group_as_internal` | `groups.update_group` |
| `auth.get_user_assigned_groups` | `users.read_user_group_memberships` |
| `auth.get_user_groups_to_sync` | `groups.get_groups` |
| `auth.process_external_group_member_sync_by_mapping` | **None** (internal) |
| `auth.process_external_group_member_sync` | **None** (internal) |
| `auth.search_user_groups` | `groups.get_group` |
| `auth.ensure_user_groups` | `groups.create_group` / `groups.delete_group` |
| `auth.ensure_user_group_mappings` | `groups.create_mapping` / `groups.delete_mapping` |

## Permission Functions (`022_functions_auth_permission.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.throw_no_access` | **None** (utility) |
| `auth.has_permissions` | **None** (core check function) |
| `auth.has_permission` | **None** (core check function) |
| `auth.get_effective_group_permissions` | `groups.get_permissions` |
| `auth.get_assigned_group_permissions` | `groups.get_permissions` |
| `auth.set_permission_as_assignable` | `permissions.update_permission` |
| `auth.assign_permission` | `permissions.assign_permission` |
| `auth.unassign_permission` | `permissions.unassign_permission` |
| `auth.create_permission` | `permissions.add_permission` |
| `auth.get_all_permissions` | `permissions.get_perm_sets` |
| `auth.get_perm_sets` | `permissions.get_perm_sets` |
| `auth.create_perm_set` | `permissions.create_permission_set` |
| `auth.update_perm_set` | `permissions.update_permission_set` |
| `auth.add_perm_set_permissions` | `permissions.update_permission_set` |
| `auth.delete_perm_set_permissions` | `permissions.update_permission_set` |
| `auth.get_user_permissions` | `users.get_permissions` |
| `auth.seed_permission_data` | **None** |
| `auth.ensure_groups_and_permissions` | `authentication.ensure_permissions` |
| `auth.get_users_groups_and_permissions` | `authentication.get_users_groups_and_permissions` |
| `auth.get_user_assigned_permissions` | `users.get_permissions` |
| `auth.search_permissions` | `permissions.read_permissions` |
| `auth.search_perm_sets` | `permissions.read_perm_sets` |
| `auth.ensure_permissions` | `permissions.add_permission` / `permissions.delete_permission` |
| `auth.ensure_perm_sets` | `permissions.create_permission_set` / `permissions.delete_permission_set` |

## Tenant Functions (`023_functions_auth_tenant.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.get_tenants` | `tenants.get_tenants` |
| `auth.get_tenant_by_id` | **None** |
| `auth.get_tenant_users` | `tenants.get_users` |
| `auth.get_tenant_groups` | `tenants.get_groups` |
| `auth.get_tenant_members` | `tenants.get_tenants` |
| `auth.delete_tenant` | `tenants.delete_tenant` |
| `auth.delete_tenant_by_uuid` | `tenants.delete_tenant` |
| `auth.get_user_available_tenants` | `users.get_available_tenants` (conditional) |
| `auth.create_user_tenant_preferences` | `users.create_user_tenant_preferences` (conditional) |
| `auth.update_user_tenant_preferences` | `users.update_user_tenant_preferences` (conditional) |
| `auth.get_user_last_selected_tenant` | `users.get_data` (conditional) |
| `auth.update_user_last_selected_tenant` | `users.update_last_selected_tenant` (conditional) |
| `auth.get_all_tenants` | **None** |
| `auth.create_tenant` | `tenants.create_tenant` |
| `auth.update_tenant` | `tenants.update_tenant` |
| `auth.search_tenants` | `tenants.read_tenants` |

## Provider Functions (`024_functions_auth_provider.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.validate_provider_is_active` | **None** (validation helper) |
| `auth.validate_provider_allows_group_mapping` | **None** (validation helper) |
| `auth.validate_provider_allows_group_sync` | **None** (validation helper) |
| `auth.ensure_provider` | delegates to `create_provider` |
| `auth.create_provider` | `providers.create_provider` |
| `auth.update_provider` | `providers.update_provider` |
| `auth.delete_provider` | `providers.delete_provider` |
| `auth.enable_provider` | `providers.update_provider` |
| `auth.disable_provider` | `providers.update_provider` |
| `auth.get_provider_users` | `manage_provider.get_users` |
| `auth.get_providers` | `providers` |

## Token Functions (`025_functions_auth_token.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.create_token` | `tokens.create_token` |
| `auth.set_token_as_used` | `tokens.set_as_used` |
| `auth.set_token_as_used_by_token` | delegates to `set_token_as_used` |
| `auth.set_token_as_failed` | `tokens.set_as_used` |
| `auth.set_token_as_failed_by_token` | delegates to `set_token_as_failed` |
| `auth.validate_token` | `tokens.validate_token` |

## API Key Functions (`026_functions_auth_apikey.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.generate_api_key_username` | **None** (utility) |
| `auth.generate_api_key` | **None** (utility) |
| `auth.generate_api_secret` | **None** (utility) |
| `auth.generate_api_secret_hash` | **None** (utility) |
| `auth.create_api_key` | `api_keys.create_api_key` |
| `auth.search_api_keys` | `api_keys.search` |
| `auth.get_api_key_permissions` | **None** |
| `auth.update_api_key` | `api_keys.update_api_key` |
| `auth.assign_api_key_permissions` | `api_keys.update_permissions` |
| `auth.unassign_api_key_permissions` | `api_keys.update_permissions` |
| `auth.delete_api_key` | `api_keys.delete_api_key` |
| `auth.update_api_key_secret` | `api_keys.update_api_secret` |
| `auth.validate_api_key` | `api_keys.validate_api_key` |
| `auth.create_outbound_api_key` | `api_keys.create_api_key` |
| `auth.get_outbound_api_key` | `api_keys.search` |
| `auth.get_outbound_api_key_by_id` | `api_keys.search` |
| `auth.get_outbound_api_key_secret` | `api_keys.read_outbound_secret` |
| `auth.get_outbound_api_key_secret_by_id` | `api_keys.read_outbound_secret` |
| `auth.update_outbound_api_key` | `api_keys.update_api_key` |
| `auth.update_outbound_api_key_secret` | `api_keys.update_api_secret` |
| `auth.search_outbound_api_keys` | `api_keys.search` |
| `auth.delete_outbound_api_key` | `api_keys.delete_api_key` |

## Owner Functions (`027_functions_auth_owner.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.has_owner` | **None** (query utility) |
| `auth.is_owner` | **None** (query utility) |
| `auth.create_owner` | **None** (uses `verify_owner_or_permission` pattern) |
| `auth.delete_owner` | **None** (uses `verify_owner_or_permission` pattern) |

## Event Functions (`028_functions_auth_event.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.create_user_event` | **None** (audit logging wrapper) |
| `auth.search_user_events` | `authentication.read_user_events` |
| `auth.get_user_audit_trail` | `authentication.read_user_events` |
| `auth.get_security_events` | `authentication.read_user_events` |

## Resource Access Functions (`035_functions_resource_access.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.has_resource_access` | **None** (core check function) |
| `auth.filter_accessible_resources` | **None** (core check function) |
| `auth.get_resource_access_flags` | **None** (read-only query) |
| `auth.get_resource_access_matrix` | **None** (read-only query) |
| `auth.assign_resource_access` | `resources.grant_access` |
| `auth.deny_resource_access` | `resources.deny_access` |
| `auth.revoke_resource_access` | `resources.revoke_access` |
| `auth.revoke_all_resource_access` | `resources.revoke_access` |
| `auth.get_resource_grants` | `resources.get_grants` |
| `auth.get_user_accessible_resources` | `resources.get_grants` (unless querying self) |
| `auth.create_resource_type` | `resources.create_resource_type` |
| `auth.update_resource_type` | `resources.create_resource_type` |
| `auth.ensure_resource_types` | `resources.create_resource_type` |
| `auth.get_resource_types` | **None** (public metadata) |
| `auth.ensure_access_flags` | `resources.create_resource_type` |
| `auth.ensure_resource_type_flags` | `resources.create_resource_type` |
| `auth.get_access_flags` | **None** (public metadata) |

## MFA Functions (`038_functions_mfa.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.enroll_mfa` | `mfa.enroll_mfa` |
| `auth.confirm_mfa_enrollment` | `mfa.confirm_mfa_enrollment` |
| `auth.disable_mfa` | `mfa.disable_mfa` |
| `auth.get_mfa_status` | `mfa.get_mfa_status` |
| `auth.create_mfa_challenge` | `mfa.create_mfa_challenge` |
| `auth.verify_mfa_challenge` | `mfa.verify_mfa_challenge` |

## MFA Policy Functions (`040_functions_mfa_policy.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.reset_mfa` | `mfa.reset_mfa` |
| `auth.create_mfa_policy` | `mfa.mfa_policy.create_mfa_policy` |
| `auth.delete_mfa_policy` | `mfa.mfa_policy.delete_mfa_policy` |
| `auth.get_mfa_policies` | `mfa.mfa_policy.get_mfa_policies` |
| `auth.is_mfa_required` | `mfa.get_mfa_status` |

## Invitation Functions (`042_functions_invitation.sql`)

| Function | Permission Required |
|----------|-------------------|
| `auth.create_invitation` | `invitations.create_invitation` |
| `auth.accept_invitation` | `invitations.accept_invitation` |
| `auth.reject_invitation` | `invitations.reject_invitation` |
| `auth.revoke_invitation` | `invitations.revoke_invitation` |
| `auth.get_invitations` | `invitations.get_invitations` |
| `auth.get_invitation_actions` | `invitations.get_invitations` |
| `auth.create_invitation_from_template` | `invitations.create_invitation` |
| `auth.create_invitation_template` | `invitations.manage_templates` |
| `auth.update_invitation_template` | `invitations.manage_templates` |
| `auth.delete_invitation_template` | `invitations.manage_templates` |

---

## Functions with No Permission Check (Review Candidates)

Functions marked **None** above fall into these categories:

### Intentionally unchecked (correct)

| Function | Reason |
|----------|--------|
| `auth.has_permission` / `auth.has_permissions` | Core check functions — checking permission to check permissions would be circular |
| `auth.has_resource_access` / `auth.filter_accessible_resources` | Core ACL check functions |
| `auth.throw_no_access` | Utility that throws an error |
| `auth.is_group_member` / `auth.can_manage_user_group` | Low-level role-checking utilities |
| `auth.has_owner` / `auth.is_owner` | Read-only ownership queries |
| `auth.create_owner` / `auth.delete_owner` | Uses `verify_owner_or_permission` pattern (checks ownership OR permission) |
| `auth.validate_provider_*` | Internal validation helpers |
| `auth.generate_api_key*` | Pure utility functions (no data access) |
| `auth.create_user_event` | Audit logging — must always succeed |
| `auth.seed_permission_data` | Bootstrap function for initial setup |
| `auth.ensure_user_info` / `auth.ensure_user_from_provider` | Provider login flow — called during authentication before permissions are established |
| `auth.get_user_by_provider_oid` | Provider login flow |
| `auth.is_blacklisted` | Read-only check used during login flow |
| `auth.process_external_group_member_sync*` | Internal sync operations |
| `auth.get_resource_types` / `auth.get_access_flags` | Public metadata (like permission codes) |
| `auth.get_resource_access_flags` / `auth.get_resource_access_matrix` | Read-only queries on user's own access |

### Worth reviewing

| Function | Concern |
|----------|---------|
| `auth.update_user_data` | Writes user data with no permission check |
| `auth.get_api_key_permissions` | Returns API key permissions with no check |
| `auth.get_user_by_id` | Returns full user record with no check |
| `auth.get_tenant_by_id` | Returns tenant record with no check |
| `auth.get_all_tenants` | Lists all tenants with no check |
