#! /bin/bash

if [ "${USER}" == "mapper" ]; then
    dbname="Africa"
elif [ "${USER}" == "sandbox" ]; then
    dbname="AfricaSandbox"
else
    echo "$0 must be run as user mapper or user sandbox"
    exit 1
fi
psql -U postgis $dbname </u/${USER}/afmap/pgsql/update_newqaqc_sites_fields.sql
