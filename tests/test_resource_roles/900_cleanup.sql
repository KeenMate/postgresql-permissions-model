set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Resource Roles Test Suite - Cleanup';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE '';
END $$;

DO $$
DECLARE
    __user_id_1 bigint;
    __user_id_2 bigint;
    __user_id_3 bigint;
    __group_id_1 integer;
    __group_id_2 integer;
    __tenant_id_2 integer;
BEGIN
    SELECT val FROM _rr_test_data WHERE key = 'user_id_1' INTO __user_id_1;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_2' INTO __user_id_2;
    SELECT val FROM _rr_test_data WHERE key = 'user_id_3' INTO __user_id_3;
    SELECT val::integer FROM _rr_test_data WHERE key = 'group_id_1' INTO __group_id_1;
    SELECT val::integer FROM _rr_test_data WHERE key = 'group_id_2' INTO __group_id_2;
    SELECT val::integer FROM _rr_test_data WHERE key = 'tenant_id_2' INTO __tenant_id_2;

    -- Role assignments cascade via FK when roles or users/groups are deleted
    DELETE FROM const.resource_role WHERE source = 'test_roles';
    DELETE FROM const.resource_role WHERE source = 'test_crud';
    DELETE FROM const.resource_role WHERE source = 'test_bulk';

    -- Resource type flags
    DELETE FROM const.resource_type_flag WHERE resource_type_code IN ('asset', 'asset.file');

    -- Resource types
    DELETE FROM const.resource_type WHERE code = 'asset.file';
    DELETE FROM const.resource_type WHERE code = 'asset';

    -- Direct grants (cascade from user/group delete, but clean up any orphans)
    DELETE FROM auth.resource_access WHERE tenant_id IN (1, __tenant_id_2)
        AND resource_type IN ('asset', 'asset.file');

    -- Groups (cascade deletes group members)
    DELETE FROM auth.user_group WHERE user_group_id IN (__group_id_1, __group_id_2);

    -- Users
    DELETE FROM auth.user_info WHERE user_id IN (__user_id_1, __user_id_2, __user_id_3);

    -- Tenant
    DELETE FROM auth.tenant WHERE tenant_id = __tenant_id_2;

    DROP TABLE IF EXISTS _rr_test_data;

    RAISE NOTICE 'CLEANUP: Done';
END $$;
