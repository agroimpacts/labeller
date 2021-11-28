#! /bin/bash

if [ "${USER}" != "mapper" ]; then
    echo "$0 must be run as user mapper"
    exit 1
fi
echo "Do you want to migrate the AfricaSandbox DB to the Africa DB and initialize it?"
select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done
read -s -p "Enter postgres password: " postgres_pw
echo
read -s -p "Enter postgis password: " postgis_pw
echo

SDB=AfricaSandbox
DDB=Africa

# Script directory.
SDIR=`dirname $0`

#if false; then
# Make DB user postgis into a superuser temporarily.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_alter_su.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

# Backup the sandbox and production DBs.
echo "About to backup $SDB database to $SDB.pgdump. This could take some time..."
PGPASSWORD=$postgis_pw pg_dump -Fc -f $SDIR/migration/$SDB.pgdump -U postgis $SDB
if [[ $? != 0 ]]; then
    exit 1
fi
echo "About to backup $DDB database to $DDB.pgdump. This could take some time..."
PGPASSWORD=$postgis_pw pg_dump -Fc -f $SDIR/migration/$DDB.pgdump -U postgis $DDB
if [[ $? != 0 ]]; then
    exit 1
fi

# Recreate the production DB.
PGPASSWORD=$postgis_pw psql -U postgis $SDB <<EOD
drop database "$DDB";
create database "$DDB";
EOD
if [[ $? != 0 ]]; then
    exit 1
fi

# Restore the AfricaSandbox DB as the Africa DB.
echo "About to restore $SDB.pgdump to $DDB database. This could take some time..."
PGPASSWORD=$postgis_pw pg_restore -d "$DDB" -U postgis $SDIR/migration/$SDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi

# Edit the new Africa database in preparation for starting up a production run.
# This includes clearing out some GIS tables that will be repopulated below and in production.
$SDIR/clear_db.sh $postgis_pw
if [[ $? != 0 ]]; then
    exit 1
fi

# Import the worker_data, qual_worker_data, roles, user_invites, users, users_roles,
# incoming_names, and iteration_metrics from the most recent Africa DB backup.
# Clean and update master_grid
pg_restore --data-only -t worker_data -f $SDIR/migration/${DDB}_worker_data.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t roles -f $SDIR/migration/${DDB}_roles.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t user_invites -f $SDIR/migration/${DDB}_user_invites.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t users -f $SDIR/migration/${DDB}_users.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t users_roles -f $SDIR/migration/${DDB}_users_roles.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t incoming_names -f $SDIR/migration/${DDB}_incoming_names.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
pg_restore --data-only -t iteration_metrics -f $SDIR/migration/${DDB}_iteration_metrics.sql $SDIR/migration/$DDB.pgdump
if [[ $? != 0 ]]; then
    exit 1
fi
#fi
PGPASSWORD=$postgis_pw psql -U postgis $DDB <<EOD
delete from worker_data;
delete from user_invites;
delete from users_roles;
delete from users;
delete from roles;
delete from incoming_names;
delete from iteration_metrics;
\i $SDIR/migration/${DDB}_roles.sql
\i $SDIR/migration/${DDB}_users.sql
\i $SDIR/migration/${DDB}_users_roles.sql
\i $SDIR/migration/${DDB}_user_invites.sql
\i $SDIR/migration/${DDB}_worker_data.sql
\i $SDIR/migration/${DDB}_iteration_metrics.sql
\i $SDIR/migration/${DDB}_incoming_names.sql

update system_data set value = (select coalesce(max(iteration), 0) from iteration_metrics) where key = 'IterationCounter';
update master_grid set avail='T' where avail in ('Q', 'I', 'F', 'N');
update master_grid set avail='Q' where name in (select name from kml_data_static where kml_type='Q');
update master_grid set avail='I' where name in (select name from kml_data_static where kml_type='I');
EOD
if [[ $? != 0 ]]; then
    exit 1
fi

# Update the configuration parameters with the production values.
PGPASSWORD=$postgis_pw psql -f $SDIR/updateConfiguration.sql -U postgis $DDB
if [[ $? != 0 ]]; then
    exit 1
fi

# Revoke superuser role from DB user postgis.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_normal.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

echo
echo "DB migration complete!"
