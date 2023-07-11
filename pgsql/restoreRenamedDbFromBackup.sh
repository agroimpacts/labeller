#! /bin/bash
  
echo "Ensure that postgresql's pg_hba.conf will allow user 'postgis' to connect to DB 'postgres',"
echo "and will also allow connections to the new database so as to enable restoring to it."
echo "If you change pg_hba.conf, restart the postgresql server before running this script."
read -n1 -r -p "Press any key to continue..." key

read -p "Name of new database to create and restore into: " db
read -p "Path of pgdump file to restore from: " dump
if [[ "$db" == "" || "$dump" == "" ]]; then
    echo "You must specify both a DB name and a dump filename."
    exit 1
fi
read -s -p "Enter postgres password: " postgres_pw
echo
read -s -p "Enter postgis password: " postgis_pw
echo

# Script directory.
SDIR=`dirname $0`

# Make DB user postgis into a superuser temporarily.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_alter_su.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

PGPASSWORD=$postgis_pw psql -U postgis postgres <<EOD
drop database "$db";
create database "$db";
EOD

echo "About to restore $dump to $db database. This could take some time..."
PGPASSWORD=$postgis_pw pg_restore -d "$db" -U postgis $dump

# Revoke superuser role from DB user postgis.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_normal.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

echo "Done!"
echo "If you modified postgresql's pg_hba.conf to allow this restore,"
echo "copy it back to the .../pgsql directory as described in the .../pgsql/README file."
