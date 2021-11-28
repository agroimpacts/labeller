#! /bin/bash

DATADIR=`dirname $0`/data

if [ -f $DATADIR/$1_schema.sql.2 ]; then
        mv $DATADIR/$1_schema.sql.2 $DATADIR/$1_schema.sql.3
fi
if [ -f $DATADIR/$1_schema.sql.1 ]; then
        mv $DATADIR/$1_schema.sql.1 $DATADIR/$1_schema.sql.2
fi
if [ -f $DATADIR/$1_schema.sql ]; then
        mv $DATADIR/$1_schema.sql $DATADIR/$1_schema.sql.1
fi
pg_dump --create --schema-only --column-inserts --file=$DATADIR/$1_schema.sql -U postgres $1
