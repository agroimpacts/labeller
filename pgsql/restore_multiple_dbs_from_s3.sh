#! /bin/bash
# reads in latest version of multiple dbs backups and adds them into new 
# databases named for

if [ "${USER}" == "mapper" ]; then
    DB="Africa"
else
    echo "$0 must be run as user mapper"
    exit 1
fi

# Read in table
# Enter table names into array
declare -a tablearray

# Load file into array.
if [ ! -f dbs_to_restore.txt ]; then
    echo "'dbs_to_restore.txt' file not found! You need to have this file" \
    "if you want to restore individual tables. Create it and put one table" \
    "name per line."
    exit 1
fi

let i=0
while IFS=$'\n' read -r line_data; do
    tablearray[i]="${line_data}"
    ((++i))
done < dbs_to_restore.txt

echo "Do you want to restore these tables from backup on S3 into $DB?"
for item in ${tablearray[*]}
do
    echo $item
done

# # pw directory
PGDIR=/home/mapper/labeller/pgsql
export PGPASSFILE=$PGDIR/pgpassfile_mapper
# echo $postgres_pw

select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done


# # details of db on S3
read -s -p "Enter postgis password: " postgis_pw
echo

# Paths
SDIR=`dirname $0`  # Script directory.
s3path=s3:\/\/activemapper

# Make DB user postgis into a superuser temporarily.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_alter_su.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

for db in ${tablearray[*]}
do
    # get latest db backup from s3
    lastbackup=`aws s3 ls $s3path/backups/database/$db/ \
      --recursive | sort | tail -n 1 | awk '{print $4}'`
    # IFS='/' read -r -a array <<< "$lastbackup"  # get basename
    # backupname=$(echo "${array[-1]}")
    ec2file=$PGDIR/migration/$db.pgdump  # transfer file path
    # echo $ec2file
    
    # transfer the file over
    aws s3 cp $s3path/$lastbackup $ec2file
    
    # drop and create new database
    PGPASSWORD=$postgis_pw dropdb -U postgis "$db";
    PGPASSWORD=$postgis_pw createdb -U postgis "$db";

    echo "About to restore $db.pgdump to $db database. This could take some time..."
    PGPASSWORD=$postgis_pw pg_restore -d "$db" -U postgis $ec2file
    
    # # Remove back-up file from instance
    echo "Cleaning up: deleting" $ec2file
    rm -f $ec2file
    if [[ $? != 0 ]]; then
        exit 1
    fi
done

# Revoke superuser role from DB user postgis.
PGPASSWORD=$postgres_pw psql -f $SDIR/role_normal.sql -U postgres postgres
if [[ $? != 0 ]]; then
    exit 1
fi

echo "Done!"
echo "If you modified postgresql's pg_hba.conf to allow this restore,"
echo "copy it back to the .../pgsql directory as described in the .../pgsql/README file."
