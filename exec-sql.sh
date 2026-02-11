#!/bin/bash
# exec-sql.sh - Run SQL commands or scripts against the database
#
# Usage:
#   ./exec-sql.sh "SELECT * FROM auth.user_info;"     # Run inline SQL
#   ./exec-sql.sh -f script.sql                        # Run SQL file
#   ./exec-sql.sh                                      # Interactive psql

# Load environment files
if [ -f "debee.env" ]; then
    set -a
    source debee.env
    set +a
fi

if [ -f ".debee.env" ]; then
    set -a
    source .debee.env
    set +a
fi

# Use DBDESTDB if set, otherwise default
DB="${DBDESTDB:-postgresql_permissionmodel}"

# Run psql with loaded environment
if [ "$1" == "-f" ] && [ -n "$2" ]; then
    # Run SQL file
    psql -d "$DB" -f "$2"
elif [ -n "$1" ]; then
    # Run inline SQL
    psql -d "$DB" -c "$1"
else
    # Interactive mode
    psql -d "$DB"
fi
