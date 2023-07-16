#! /bin/bash
  
echo "Ensure that postgresql's pg_hba.conf will allow user 'postgis' to connect to DB 'postgres',"
echo "and will also allow connections to the new database so as to enable restoring to it."
echo "If you change pg_hba.conf, restart the postgresql server before running this script."
read -n1 -r -p "Press any key to continue..." key

echo "Make sure there is no connection to the database first, as it will cause"
echo "the restore to fail. You can look for idle connections with"
echo "ps -ef | grep postgres"
read -n1 -r -p "Press any key to continue..." key


# details of db on S3
echo "In what S3 folder (prefix) is the back-up?"
read -p "Enter bucket prefix in s3://..backups/database/: " s3folder
echo "From what date was the back-up?"
read -p "Enter date as YYYY-MM-DD (e.g. 2018-11-14): " ymd
echo "What is the name of the dump file you need?"
read -p "Name of pgdump file in folder from: " dump
read -p "Name of new database to create and restore into: " db
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

# extract bucket
for item in ${config_array[*]}
do
    if [[ $item == *"bucket"* ]]; then
        bucket=`echo "$item" | cut -d'"' -f 2`
    fi
done
S3PATH=s3://$bucket/backups/database/$s3folder/$ymd
#S3FILE=$(aws s3 ls $S3PATH | grep $dump)
S3FILE=$S3PATH/$dump.pgdump
#if [ -z "$S3FILE" ]; then
#    echo $dump "doesn't exist in" $S3PATH
#    exit 1
#fi

#echo "Fetching" $S3FILE "from S3"
EC2FILE=$SDIR/migration/$dump.pgdump
aws s3 cp $S3FILE $EC2FILE
if [[ $? != 0 ]]; then
    exit 1
fi

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
PGPASSWORD=$postgis_pw pg_restore -d "$db" -U postgis $EC2FILE

# Revoke superuser role from DB user postgis.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_normal.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

# Remove back-up file from instance
echo "Cleaning up: deleting" $EC2FILE
rm -f $EC2FILE
if [[ $? != 0 ]]; then
    exit 1
fi

echo "Done!"
echo "If you modified postgresql's pg_hba.conf to allow this restore,"
echo "copy it back to the .../pgsql directory as described in the .../pgsql/README file."
