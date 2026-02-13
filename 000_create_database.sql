-- Default database name; override via: psql -v db_name=other_db -f 000_create_database.sql
\set db_name postgresql_permissionmodel

-- ensure user role (create if not exists, using db_name as both role name and password)
select format('CREATE ROLE %I WITH PASSWORD %L LOGIN', :'db_name', :'db_name')
where not exists (select from pg_roles where rolname = :'db_name')
\gexec

select pg_terminate_backend(pg_stat_activity.pid)
from pg_stat_activity
where pg_stat_activity.datname = :'db_name'
	and pid <> pg_backend_pid();

drop database if exists :"db_name";
create database :"db_name" with owner :"db_name";