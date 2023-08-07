@echo off
set CREATE_DATABASE=00_create_database.sql
set CREATE_BASIC_STRUCTURE=10_create_basic_structure.sql
set CREATE_VERSION_MANAGEMENT=20_version_management.sql
set CREATE_HELPERS=30_create_helpers.sql
set CREATE_PERSMISSIONS=40_create_permissions.sql
set CREATE_FIX_PERMISSIONS=99_fix_permissions.sql
set SCRIPT_DIR=./
set DB_NAME=km_permissions
set PGPASSWORD=Password3000!!
SET PGCLIENTENCODING=utf-8
chcp 65001

psql -U postgres -c "\i %SCRIPT_DIR%/%CREATE_DATABASE%;"
psql -U postgres -d %DB_NAME% -c "\i %SCRIPT_DIR%/%CREATE_BASIC_STRUCTURE%;
psql -U postgres -d %DB_NAME% -c "\i %SCRIPT_DIR%/%CREATE_VERSION_MANAGEMENT%;
psql -U postgres -d %DB_NAME% -c "\i %SCRIPT_DIR%/%CREATE_HELPERS%;
psql -U postgres -d %DB_NAME% -c "\i %SCRIPT_DIR%/%CREATE_PERSMISSIONS%;
psql -U postgres -d %DB_NAME% -c "\i %SCRIPT_DIR%/%CREATE_FIX_PERMISSIONS%;

pause