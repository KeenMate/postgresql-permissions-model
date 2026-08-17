-- ============================================================================
-- Purge destroys the tenant and burns its code forever (identity ledger)
-- ============================================================================
do $$
declare
    __uuid    uuid;
    __tid     int;
    __row     int;
    __ledger  int;
    __purged  timestamptz;
    __d_uuid  uuid;
begin
    raise notice 'TEST 4: purge + permanent identity ledger';

    -- Soft delete then purge (two-step)
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Purge', 'sd_purge') ct into __uuid;
    select tenant_id from auth.tenant where uuid = __uuid into __tid;
    perform auth.delete_tenant('sd_test', 1, 'c', __uuid);
    perform auth.purge_tenant('sd_test', 1, 'c', __uuid);

    -- Tenant row physically gone
    select count(*) from auth.tenant where tenant_id = __tid into __row;
    if __row = 0 then
        raise notice '  PASS: tenant row physically removed after purge';
    else
        raise exception '  FAIL: tenant row still present after purge (%)', __row;
    end if;

    -- Identity ledger retains the code and stamps purged_at
    select count(*), max(purged_at) from auth.tenant_identity where code = 'sd_purge' into __ledger, __purged;
    if __ledger = 1 and __purged is not null then
        raise notice '  PASS: identity ledger retained + purged_at stamped';
    else
        raise exception '  FAIL: ledger state count=% purged_at=%', __ledger, __purged;
    end if;

    -- Explicit code can never be reused
    begin
        perform auth.create_tenant('sd_test', 1, 'c', 'SD Purge Redux', 'sd_purge');
        raise exception '  FAIL: reusing a purged code was allowed';
    exception when sqlstate '34004' then
        raise notice '  PASS: purged code cannot be reused (34004)';
    end;

    -- Title-derived code is burned too: create by title only, purge, recreate by same title
    select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Derived Name') ct into __d_uuid;
    perform auth.delete_tenant('sd_test', 1, 'c', __d_uuid);
    perform auth.purge_tenant('sd_test', 1, 'c', __d_uuid);
    begin
        perform auth.create_tenant('sd_test', 1, 'c', 'SD Derived Name');
        raise exception '  FAIL: recreating by same title (derived code) was allowed';
    exception when sqlstate '34004' then
        raise notice '  PASS: same-title / derived-code reuse blocked (34004)';
    end;

    -- A soft-deleted (not purged) code is also unreusable while the row lives
    declare __live_uuid uuid;
    begin
        select ct.__uuid from auth.create_tenant('sd_test', 1, 'c', 'SD Soft Only', 'sd_soft_only') ct into __live_uuid;
        perform auth.delete_tenant('sd_test', 1, 'c', __live_uuid);
        begin
            perform auth.create_tenant('sd_test', 1, 'c', 'SD Soft Only Redux', 'sd_soft_only');
            raise exception '  FAIL: reusing a soft-deleted code was allowed';
        exception when sqlstate '34004' then
            raise notice '  PASS: soft-deleted code cannot be reused (34004)';
        end;
    end;
end $$;
