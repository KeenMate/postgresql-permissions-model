-- ============================================================================
-- Restore reverses a soft delete and re-grants access
-- ============================================================================
do $$
declare
    __uuid       uuid;
    __tid        int;
    __member     bigint;
    __username   text;
    __gid        int;
    __deleted_at timestamptz;
    __available  int;
begin
    raise notice 'TEST 3: restore reverses a soft delete';

    select r.__user_id, r.__username
    from auth.register_user('sd_test', 1, 'c', 'sd_restore@test.com', 'h', 'SD Restore') r
    into __member, __username;

    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Restore Tenant', 'sd_restore') ct into __uuid;
    select tenant_id from auth.tenant where uuid = __uuid into __tid;
    select user_group_id from auth.user_group where tenant_id = __tid and title = 'Tenant Members' into __gid;
    perform unsecure.create_user_group_member('sd_test', 1, 'c', __gid, __member, __tid);

    perform auth.delete_tenant('sd_test', 1, 'c', __uuid);
    perform auth.restore_tenant('sd_test', 1, 'c', __uuid);

    select deleted_at from auth.tenant where tenant_id = __tid into __deleted_at;
    if __deleted_at is null then
        raise notice '  PASS: deleted_at cleared after restore';
    else
        raise exception '  FAIL: deleted_at still set after restore';
    end if;

    select count(*) from auth.get_user_available_tenants(1, 'c', __member)
     where __tenant_id = __tid into __available;
    if __available = 1 then
        raise notice '  PASS: tenant available again after restore';
    else
        raise exception '  FAIL: tenant not available after restore (%)', __available;
    end if;
end $$;
