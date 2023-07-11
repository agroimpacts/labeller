#! /usr/bin/python
## Author: Lei Song
## To select the N sites during the working.

import sys
import os
import time
import psycopg2
import numpy as np
from datetime import datetime as DT
from MappingCommon import MappingCommon


# Function of selecting N sites
# Hardcoded
kml_type = MappingCommon.KmlNormal  # Type of n sites
fwt = 5  # Minimum value for the proportion of being a field

# Connect to the database
mapc = MappingCommon()
log_file_path = mapc.projectRoot + "/log"

# Record daemon start time
pstart_string = "select_n_sites: Daemon starting up at " + \
                str(DT.now()) + os.linesep

# Initialize txt to log database error message
log_hdr = "Error messages from select_n_sites" + \
          os.linesep

dberrfname = log_file_path + "/sites_dbase_error.log"
k = open(dberrfname, "a+")
k.write(log_hdr)
k.close()

np.set_printoptions(precision=4)  # Display milliseconds for time stamps

# Initialize Rlog file to record daemon start time, which kml ids written & when
rlog_hdr = "Log of n sites selecting start, ids written & times" + \
           os.linesep
logfname = log_file_path + "/generateSites.log"  # log file name
k = open(logfname, "a+")
k.write(rlog_hdr)

# Write out daemon start stamp
k.write(pstart_string)
k.close()

while True:
    # Query polling interval
    kml_polling_interval = int(mapc.getConfiguration('KMLPollingInterval'))

    # Target batch size: should be at least 500
    kml_batch_size = int(mapc.getConfiguration('NKMLBatchSize'))

    # how many unmapped kmls should there be, at a minimum
    min_avail_kml = int(mapc.getConfiguration('MinAvailNKMLTarget'))

    # how many unmapped kmls are there?
    mapc.cur.execute(
        "select count(*) from kml_data k where not exists "
        "(select true from hit_data h where h.name = k.name "
        "and delete_time is null) and (kml_type = 'N' or kml_type = 'F') "
        "and mapped_count = 0")
    avail_kml_count = int(mapc.cur.fetchone()[0])
    mapc.dbcon.commit()

    # Get the anchor of loading data
    first_avail_line = int(mapc.getSystemData('firstAvailLine'))

    # Select new grid cells for conversion to kmls if N unmapped < min_avail_kml
    if avail_kml_count < min_avail_kml:
        # Step 1. Poll the database to see which grid IDs are still available
        # Including fwts >= 5, there might be less than 500 once.
        mapc.cur.execute("select name from master_grid where avail = 'T' and gid >= " +
                         str(first_avail_line) + " and gid <= " +
                         str(first_avail_line + kml_batch_size - 1) +
                         " and fwts >= " + str(fwt))
        xy_tabs = mapc.cur.fetchall()
        mapc.dbcon.commit()

        try:
            # Step 2. Update database tables
            # Update kml_data to show new names added and their kml_type
            # Update master to show grid is no longer available for selecting/writing
            for row in xy_tabs:
                xy_tab = row + (kml_type, 0)
                insert_query = "insert into kml_data (name, kml_type, mapped_count) values (%s, %s, %s);"
                mapc.cur.execute(insert_query, xy_tab)
                mapc.cur.execute("update master_grid set avail='%s' where name = '%s'" % (kml_type, row[1]))
            mapc.dbcon.commit()

            # Update the first_avail_line in configuration
            new_line = first_avail_line + kml_batch_size
            mapc.setSystemData('firstAvailLine', new_line)

            end_time = str(DT.now())

            # Write out kmlID log
            names = ', '.join("'{}'".format(row) for row in dict(xy_tabs).values())
            k = open(logfname, "a+")
            k.write(names + os.linesep)
            k.write("select_n_sites: Script stopping up at " + end_time + os.linesep)
            k.close()

        except psycopg2.DatabaseError, err:
            print "Error updating database, rollback"
            mapc.cur.execute("ROLLBACK")  # In order to recover the database
            mapc.dbcon.commit()
            error = "select_n_sites: " + str(DT.now()) + " " + str(err)
            k = open(dberrfname, "a+")
            k.write(error + os.linesep)
            k.close()
            mapc.createAlertIssue("select_n_sites database error",
                                  "Alert: Check the connection and query of database for selecting n sites." +
                                  os.linesep + str(err))
            sys.exit(1)
        finally:
            if mapc.dbcon.closed == 0:
                mapc.close()

    time.sleep(kml_polling_interval)
