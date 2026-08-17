-- ============================================================================
-- Guards: protected tenants, double-delete, restore/purge state requirements
-- ============================================================================
do $$
declare
    __t1_uuid uuid;
    __uuid    uuid;
begin
    raise notice 'TEST 2: delete/restore/purge guards';

    -- (a) system tenant 1 cannot be soft-deleted
    select uuid from auth.tenant where tenant_id = 1 into __t1_uuid;
    begin
        perform auth.delete_tenant('sd_test', 1, 'c', __t1_uuid);
        raise exception '  FAIL: soft-deleting tenant 1 was allowed';
    exception when sqlstate '34007' then
        raise notice '  PASS: tenant 1 protected (34007)';
    end;

    -- (b) is_removable = false is protected
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD NonRemovable', 'sd_norem', _is_removable := false) ct into __uuid;
    begin
        perform auth.delete_tenant('sd_test', 1, 'c', __uuid);
        raise exception '  FAIL: soft-deleting non-removable tenant was allowed';
    exception when sqlstate '34007' then
        raise notice '  PASS: non-removable tenant protected (34007)';
    end;

    -- (c) double soft-delete is rejected
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Double', 'sd_double') ct into __uuid;
    perform auth.delete_tenant('sd_test', 1, 'c', __uuid);
    begin
        perform auth.delete_tenant('sd_test', 1, 'c', __uuid);
        raise exception '  FAIL: double soft-delete was allowed';
    exception when sqlstate '34005' then
        raise notice '  PASS: already-deleted rejected (34005)';
    end;

    -- (d) restoring a live (not-deleted) tenant is rejected
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Live', 'sd_live') ct into __uuid;
    begin
        perform auth.restore_tenant('sd_test', 1, 'c', __uuid);
        raise exception '  FAIL: restoring a live tenant was allowed';
    exception when sqlstate '34006' then
        raise notice '  PASS: restore requires a soft-deleted tenant (34006)';
    end;

    -- (e) purge requires soft-delete first
    begin
        perform auth.purge_tenant('sd_test', 1, 'c', __uuid);
        raise exception '  FAIL: purging a live tenant was allowed';
    exception when sqlstate '34006' then
        raise notice '  PASS: purge requires soft-delete first (34006)';
    end;
end $$;
