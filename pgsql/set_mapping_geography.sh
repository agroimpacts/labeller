#! /bin/bash
# Prepare database for new mapping geography
# Replace existing master_grid with new one, and all Q type datasets
# This does the following: 
#  - downloads grid, kml_static_grid csv, qaqcfields geojson from S3 to local 
#    migration folder
#  - deletes from master_grid kml_data_static, qaqcfields, kml_data
#  - copies from csvs into master_grid, kml_data_static
#  - copies geojson (pre) converted to csv into qaqcfields (b/c ogr has no
#    postgresql driver
# Requires new main and accuracy grid csvs and qaqc geojson to be on S3

if [ "${USER}" == "mapper" ]; then
    dbname="Africa"
else
    echo "$0 must be run as user mapper"
    exit 1
fi

echo "Executing this script will reset the database and create a new mapping"
echo "geography and training reference grid." 
echo "***All stored data will be deleted***"
echo

declare -a tablearray

# Load file into array.
if [ ! -f geography_files_to_load.txt ]; then
    echo "'geography_file_to_load.txt' file not found! You need this file " \ 
    "to update the mapping geography. Create it and put each of the" \
    "file names in, one per line, in this order, starting with their" \
    "paths/prefixes: <main_grid>.csv <kml_static_grid>.csv, <kml_static>.csv,"\ 
    "<qaqcfields>.geojson. The main grid file should be in grid/, and the" \
    " others in training_reference/. Note this assumes, for now, that they" \
    " are in s3://activemapper"
    exit 1
fi

let i=0
while IFS=$'\n' read -r line_data; do
    tablearray[i]="${line_data}"
    ((++i))
done < geography_files_to_load.txt

echo "Do you want to fetch these files from S3, clear $DB, and install them?"
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

SPATH=$(readlink -f $0)
SDIR=`dirname $SPATH`
MIGRATEDIR=$SDIR/migration
S3PATH=s3:\/\/activemapper

## Download from S3
for item in ${tablearray[*]}
do
    echo "Fetching" $item "from S3"
    filename=`basename $item`
    IFILE=$MIGRATEDIR/$filename
    S3FILE=$S3PATH/$item
    aws s3 cp $S3FILE $IFILE
    if [[ $? != 0 ]]; then
        exit 1
    fi
done

maingrid=`basename ${tablearray[0]}`
trainrefgrid=`basename ${tablearray[1]}`
trainref=`basename ${tablearray[2]}`
qaqcfields=`basename ${tablearray[3]}`

##echo $maingridfile
##echo $kmlgridfile
##echo $kmlstaticfile
#echo $qaqcfields

# Clear out most tables, doing most of clear_db.sh
PGPASSWORD=$postgis_pw psql -U postgis $dbname <<EOD
delete from user_maps;
delete from accuracy_data;
delete from assignment_history;
delete from assignment_data;
delete from qual_user_maps;
delete from qual_accuracy_data;
delete from qual_assignment_data;
delete from hit_data;
delete from scenes_data;
delete from incoming_names;

delete from kml_data;
alter sequence kml_data_gid_seq restart;

delete from kml_data_static;
create sequence kml_data_static_gid_seq increment 1 minvalue 1 maxvalue 1000000 start 1;
alter table kml_data_static
alter column gid set default nextval('kml_data_static_gid_seq');
alter sequence kml_data_static_gid_seq restart;

delete from qaqcfields;
alter sequence qaqcfields_gid_seq restart;

delete from master_grid; 
alter sequence master_grid_gid_seq1 restart;
EOD

# copy in new files
PGPASSWORD=$postgis_pw psql -U postgis $dbname <<EOD
\copy master_grid(id, x, y, name, fwts, avail) FROM '$MIGRATEDIR/$maingrid' WITH DELIMITER ',' CSV HEADER;
\copy master_grid(id, x, y, name, fwts, avail) FROM '$MIGRATEDIR/$trainrefgrid' WITH DELIMITER ',' CSV HEADER;
\copy kml_data_static (kml_type, name, hint) FROM '$MIGRATEDIR/$trainref' WITH DELIMITER ',' CSV HEADER;
\copy qaqcfields (name, category, geom_clean) FROM '$MIGRATEDIR/$qaqcfields' WITH DELIMITER ',' CSV HEADER
EOD

PGPASSWORD=$postgis_pw psql -U postgis $dbname <<EOD
insert into kml_data (kml_type, name, hint) select kml_type, name, hint from kml_data_static order by gid;
update system_data set value=0 where key='CurQaqcGid';
update system_data set value=0 where key='IterationCounter';
update system_data set value=1 where key='firstAvailLine';
EOD
## update master_grid set avail = 'T' where avail in ('I', 'Q', 'F');

#for item in ${tablearray[*]}
#do
#    echo "Fetching" $item "from S3"
#    filename=`basename $item`
#    IFILE=$MIGRATEDIR/$filename
#    rm $IFILE
#    if [[ $? != 0 ]]; then
#        exit 1
#    fi
#done
