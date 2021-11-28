#! /bin/bash

DATADIR=`dirname $0`/data

if [ -f $DATADIR/$1_data.sql.gz.2 ]; then
        mv $DATADIR/$1_data.sql.gz.2 $DATADIR/$1_data.sql.gz.3
fi
if [ -f $DATADIR/$1_data.sql.gz.1 ]; then
        mv $DATADIR/$1_data.sql.gz.1 $DATADIR/$1_data.sql.gz.2
fi
if [ -f $DATADIR/$1_data.sql.gz ]; then
        mv $DATADIR/$1_data.sql.gz $DATADIR/$1_data.sql.gz.1
fi
pg_dump --data-only --column-inserts -U postgres $1 | gzip >$DATADIR/$1_data.sql.gz
