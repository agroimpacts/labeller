import sys
import os
import click
import psycopg2
import numpy as np
from datetime import datetime as DT
home = os.environ['HOME']
projectRoot = '%s/labeller' % home
sys.path.append("%s/common" % projectRoot)
from MappingCommon import MappingCommon


# Function of selecting N sites
def select_n_sites(prop_f):
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
    logfname = log_file_path + "/generate_sites.log"  # log file name
    k = open(logfname, "a+")
    k.write(rlog_hdr)

    # Write out daemon start stamp
    k.write(pstart_string)
    k.close()

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

    # Select new grid cells for conversion to kmls if N unmapped < min_avail_kml
    if avail_kml_count < min_avail_kml:
        # Step 1. Poll the database to see which grid IDs are still available
        # Including fwts >= 5, there might be less than 500 once.
        mapc.cur.execute("select name from master_grid where avail = 'T' and fwts >= " +
                         str(fwt) + "limit %s" % min_avail_kml)
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

            mapc.cur.execute("update configuration set value = '%s' where key = '%s'"
                             % (int(prop_f), "Hit_FqaqcPercentage"))
            mapc.dbcon.commit()

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
            mapc.createAlertIssue("mode_with_n database error",
                                  "Alert: Check the connection and query of database for selecting n sites." +
                                  os.linesep + str(err))
            sys.exit(1)
        finally:
            if mapc.dbcon.closed == 0:
                mapc.close()


# Function of changing back to without Ns mode
def convert_to_without_n():
    mapc = MappingCommon()
    try:
        mapc.cur.execute("update configuration set value = '%s' where key = '%s'"
                         % (int(80), "Hit_FqaqcPercentage"))
        mapc.dbcon.commit()

    except psycopg2.DatabaseError, err:
        mapc.cur.execute("ROLLBACK")  # In order to recover the database
        mapc.dbcon.commit()
        mapc.createAlertIssue("mode_with_n database error",
                              "Alert: Check the connection and query of database for selecting n sites." +
                              os.linesep + str(err))
        sys.exit(2)


@click.command()
@click.option('--with_N', is_flag=True, help='Decide if run with Ns.')
@click.option('--prop_F', default=70, type=int, help='The proportion of F sites (Qs is always 20%).')
def main(with_n, prop_f):
    if with_n:
        select_n_sites(prop_f)
    else:
        convert_to_without_n()


if __name__ == "__main__":
    main()
