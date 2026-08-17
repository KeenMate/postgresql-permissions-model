-- ============================================================================
-- Soft delete marks the tenant, keeps the row, and blocks access at the boundary
-- ============================================================================
do $$
declare
    __tid      int;
    __uuid     uuid;
    __member   bigint;
    __username text;
    __gid      int;
    __available int;
    __deleted_at timestamptz;
    __purged_at  timestamptz;
    __row_count  int;
    __mgmt_deleted_at timestamptz;
begin
    raise notice 'TEST 1: soft delete sets deleted_at, keeps row, blocks access';

    -- A member user we can check availability for
    select r.__user_id, r.__username
    from auth.register_user('sd_test', 1, 'sd-corr', 'sd_member@test.com', 'h', 'SD Member') r
    into __member, __username;

    -- Fresh tenant + make the member a Tenant Member
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'sd-corr', 'SD Lifecycle', 'sd_life') ct into __uuid;
    select tenant_id from auth.tenant where uuid = __uuid into __tid;
    select user_group_id from auth.user_group where tenant_id = __tid and title = 'Tenant Members' into __gid;
    perform unsecure.create_user_group_member('sd_test', 1, 'c', __gid, __member, __tid);

    -- Before delete: the tenant is available to the member
    select count(*) from auth.get_user_available_tenants(1, 'sd-corr', __member)
     where __tenant_id = __tid into __available;
    if __available <> 1 then
        raise exception '  FAIL: tenant not available to member before delete (%)', __available;
    end if;
    raise notice '  PASS: tenant available before delete';

    -- Soft delete
    perform auth.delete_tenant('sd_test', 1, 'sd-corr', __uuid);

    -- Row still exists, deleted_at set, purged_at null
    select count(*), max(deleted_at), max(purged_at)
    from auth.tenant where tenant_id = __tid
    into __row_count, __deleted_at, __purged_at;
    if __row_count = 1 and __deleted_at is not null and __purged_at is null then
        raise notice '  PASS: row retained, deleted_at set, purged_at null';
    else
        raise exception '  FAIL: unexpected state count=% deleted_at=% purged_at=%', __row_count, __deleted_at, __purged_at;
    end if;

    -- Access blocked: no longer available to the member
    select count(*) from auth.get_user_available_tenants(1, 'sd-corr', __member)
     where __tenant_id = __tid into __available;
    if __available = 0 then
        raise notice '  PASS: soft-deleted tenant excluded from available tenants';
    else
        raise exception '  FAIL: soft-deleted tenant still available (%)', __available;
    end if;

    -- Management view still lists it, with deleted_at exposed
    select gt.__deleted_at from auth.get_tenants(1, 'sd-corr', 1, __tid) gt into __mgmt_deleted_at;
    if __mgmt_deleted_at is not null then
        raise notice '  PASS: get_tenants exposes deleted_at for management';
    else
        raise exception '  FAIL: get_tenants did not expose deleted_at';
    end if;
end $$;
