## Author: Lei Song
## The register new sites in incoming_names to kml_data table

# load modules
import sys
import os
import psycopg2
import numpy as np
from datetime import datetime as DT
from MappingCommon import MappingCommon


# Function of generating KMLs
def main():
    # Hardcoded
    # Type of KML (N for non-QAQC)
    kml_type = MappingCommon.KmlFQAQC

    # Connect to the database and get the path for log files
    mapc = MappingCommon()
    log_file_path = mapc.projectRoot + "/log"

    # Record daemon start time
    pstart_string = "register_f_sites: Daemon starting up at " + \
                    str(DT.now()) + os.linesep

    # Initialize csv to log database error message
    log_hdr = "Error messages from register_f_sites" + \
              os.linesep

    # Possible conflict
    dberrfname = log_file_path + "/sites_dbase_error.log"
    k = open(dberrfname, "a+")
    k.write(log_hdr)
    k.close()

    np.set_printoptions(precision=4)  # Display milliseconds for time stamps

    # Initialize Rlog file to record daemon start time, which kml ids written & when
    rlog_hdr = "Log of f sites registering start, ids written & times" + \
               os.linesep
    logfname = log_file_path + "/generateSites.log"  # log file name
    k = open(logfname, "a+")
    k.write(rlog_hdr)

    # Write out daemon start stamp
    k.write(pstart_string)
    k.close()

    # how many new incoming names so far
    mapc.cur.execute("select count(*) from incoming_names where processed = false")
    count_incoming_names = int(mapc.cur.fetchone()[0])
    mapc.dbcon.commit()

    # Add the incoming names from cvml
    if count_incoming_names > 0:
        # Step 1. Get the new incoming names
        mapc.cur.execute("select name from incoming_names where processed = false")
        rows = mapc.cur.fetchall()
        mapc.dbcon.commit()
        incoming_names = ', '.join("'{}'".format(row[0]) for row in rows)

        try:
            # Step 2. Update database tables
            # Update kml_data to show new names added and their kml_type
            for row in rows:
                xy_tab = row + (kml_type, 0)
                insert_query = "insert into kml_data (name, kml_type, mapped_count) values (%s, %s, %s);"
                mapc.cur.execute(insert_query, xy_tab)
                mapc.dbcon.commit()

            end_time = str(DT.now())

            # Write out kmlID log
            k = open(logfname, "a+")
            k.write(incoming_names + os.linesep)
            k.write("register_f_sites: Script stopping up at " + end_time + os.linesep)
            k.close()
            return True

        except psycopg2.DatabaseError, err:
            print "Error updating database, rollback"
            mapc.cur.execute("ROLLBACK")  # In order to recover the database
            mapc.dbcon.commit()
            error = "register_f_sites: " + str(DT.now()) + " " + str(err)
            k = open(dberrfname, "a+")
            k.write(error + os.linesep)
            k.close()
            mapc.createAlertIssue("register_f_sites database error",
                                  "Alert: Check the connection and query of database for F KML generating." +
                                  os.linesep + str(err))
            return False
            sys.exit(1)
        finally:
            if mapc.dbcon.closed == 0:
                mapc.close()
    else:
        mapc.createAlertIssue("None incoming names from cvml",
                              "Alert: Check if there is something wrong with cvml, there should be incoming names "
                              "always.")
        return True


if __name__ == "__main__":
    main()
