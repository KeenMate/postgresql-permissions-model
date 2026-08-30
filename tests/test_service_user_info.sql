-- ============================================================================
-- Regression: auth.create_service_user_info stores email/display_name correctly
-- ============================================================================
-- Guards against the wrapper passing _email/_display_name positionally into
-- unsecure.create_service_user_info, whose parameter order is
-- (_username, _display_name, _email) — a mismatch swaps the two columns.
-- ============================================================================

set search_path = public, const, ext, stage, helpers, internal, unsecure, auth, triggers;

do $$
declare
    __email        text := 'svc.regr@example.com';
    __display_name text := 'Service Regression';
    __new_user_id  bigint;
    __stored_email text;
    __stored_name  text;
begin
    -- Act as the system user (user_id = 1), which holds all permissions
    select r.__user_id into __new_user_id
    from auth.create_service_user_info('svc_regr_test', 1, 'svc-regr-corr',
             _username := 'svc_regr_user', _email := __email, _display_name := __display_name) r;

    select email, display_name into __stored_email, __stored_name
    from auth.user_info where user_id = __new_user_id;

    if __stored_email = __email then
        raise notice 'PASS: email stored in email column (%)', __stored_email;
    else
        raise exception 'FAIL: email column is "%" but expected "%" (email/display_name swapped?)',
            __stored_email, __email;
    end if;

    if __stored_name = __display_name then
        raise notice 'PASS: display_name stored in display_name column (%)', __stored_name;
    else
        raise exception 'FAIL: display_name column is "%" but expected "%" (email/display_name swapped?)',
            __stored_name, __display_name;
    end if;

    -- Cleanup (flat tests persist; remove what we created)
    delete from auth.user_info where user_id = __new_user_id;
    raise notice 'CLEANUP: removed service user %', __new_user_id;
end $$;
