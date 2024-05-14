do
$$
    -- ensure user role
    begin
        if not exists(select * from pg_roles where rolname = 'km_permissions') then
            create role km_permissions with password 'Password3000!!' login;
        end if;
    end;
$$;

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'km_permissions'
  AND pid <> pg_backend_pid();

drop database if exists km_permissions;
create database km_permissions with owner km_permissions;