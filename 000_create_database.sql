do
$$
    -- ensure user role
    begin
        if not exists(select * from pg_roles where rolname = 'postgresql_permissionmodel') then
            create role postgresql_permissionmodel with password 'Password3000!!' login;
        end if;
    end;
$$;

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = 'postgresql_permissionmodel'
  AND pid <> pg_backend_pid();

drop database if exists postgresql_permissionmodel;
create database postgresql_permissionmodel with owner postgresql_permissionmodel;