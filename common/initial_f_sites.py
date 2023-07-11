## Author: Lei Song
## To select the initial F sites

# load modules
import os
import sys
import psycopg2
import pandas as pd
import numpy as np
import random

import register_f_sites
from datetime import datetime as DT
from MappingCommon import MappingCommon


def main():
    # Connect to the database
    mapc = MappingCommon()
    config = mapc.parseYaml("config.yaml")
    aoiid = config['learner']['aoiid']
    log_file_path = mapc.projectRoot + "/log"
    logfname = log_file_path + "/generateSites.log"  # log file name
    dberrfname = log_file_path + "/sites_dbase_error.log"
    
    # Get the parameters
    n_f = int(mapc.getConfiguration('InitialFnum'))
    pro_hd = float(mapc.getConfiguration('ProportionHoldout'))
    pro_hd1 = float(mapc.getConfiguration('ProportionHoldout1'))

    mapc.cur.execute("SELECT count(run) FROM incoming_names")
    count_names = mapc.cur.fetchone()[0]
    mapc.dbcon.commit()
    if count_names > 0:
        mapc.cur.execute("SELECT MAX(run) FROM incoming_names")
        run = mapc.cur.fetchone()[0] + 1
        mapc.dbcon.commit()
    else:
        run = 0

    rlog_hdr = "Log of initial f sites start, ids written & times" + \
               os.linesep
    pstart_string = "Initial_f_sites: Starting up at " + \
                    str(DT.now()) + os.linesep

    k = open(logfname, "a+")
    k.write(rlog_hdr)
    k.write(pstart_string)
    k.close()

    log_hdr = "Error messages from initial_f_sites" + \
              os.linesep

    k = open(dberrfname, "a+")
    k.write(log_hdr)
    k.close()

    # Randomly get n_f F sites of Ghana from f sites pool as initial F sites
    mapc.cur.execute("select cell_id, season from scenes_data where season = 'GS'")
    ids_gs = mapc.cur.fetchall()
    mapc.cur.execute("select cell_id, season from scenes_data where season = 'OS'")
    ids_os = mapc.cur.fetchall()
    mapc.dbcon.commit()
    ids_gs = pd.DataFrame(ids_gs, columns=list(["cell_id", "season"]))
    ids_os = pd.DataFrame(ids_os, columns=list(["cell_id", "season"]))
    ids = np.array(pd.merge(ids_gs, ids_os, on='cell_id')['cell_id'], dtype=np.character)
    ids = ",".join(ids)

    sql = "select setseed(0.5); select name from master_grid where avail = 'F' and id in (%s) ORDER BY RANDOM() limit {}" % ids
    mapc.cur.execute(sql.format(n_f))
    names_f = mapc.cur.fetchall()
    mapc.dbcon.commit()

    # Split all into holdout, validate and train.
    random.seed(10)
    names_f_hd = random.sample(names_f, min(len(names_f), int(n_f * pro_hd)))
    random.seed(11)
    names_f_hd1 = random.sample(names_f_hd, min(len(names_f_hd), int(n_f * pro_hd * pro_hd1)))
    names_f_hd2 = [item for item in names_f_hd if item not in names_f_hd1]

    # Initial line in iteration_metrics
    insert_query = "insert into iteration_metrics (run, iteration, aoi, iteration_time) values (%s, %s, %s, %s);"
    mapc.cur.execute(insert_query, (run, 0, str(aoiid), DT.now()))
    mapc.dbcon.commit()

    # Write them into incoming_names table
    try:
        for name in names_f:
            if name in names_f_hd2:
                name_one = name + (run, 0, "validate")
            elif name in names_f_hd1:
                name_one = name + (run, 0, "holdout")
            else:
                name_one = name + (run, 0, "train")
            insert_query = "insert into incoming_names (name, run, iteration, usage) values (%s, %s, %s, %s);"
            mapc.cur.execute(insert_query, name_one)
            mapc.dbcon.commit()
        end_time = str(DT.now())
        names = ', '.join("'{}'".format(row[0]) for row in names_f)
        k = open(logfname, "a+")
        k.write(names + os.linesep)
        k.write("Initial_f_sites: Script stopping up at " + end_time + os.linesep)
        k.close()

    except psycopg2.DatabaseError, err:
        print "Error updating database in initial_f_sites, rollback"
        mapc.cur.execute("ROLLBACK")  # In order to recover the database
        mapc.dbcon.commit()
        error = "Initial_f_sites: " + str(DT.now()) + " " + str(err)
        k = open(dberrfname, "a+")
        k.write(error + os.linesep)
        k.close()
        mapc.createAlertIssue("Initial_f_sites database error",
                              "Alert: Check the connection and query of database for initialing f sites." +
                              os.linesep + str(err))
        sys.exit("database error.")
    finally:
        if mapc.dbcon.closed == 0:
            mapc.close()

    if register_f_sites.main():
        k = open(logfname, "a+")
        k.write("\nInitial_f_sites: register_f_sites succeed.\n")
        k.close()
    else:
        mapc.createAlertIssue("f sites generation fails",
                              "Initial_f_sites: register_f_sites fails.")
        k = open(logfname, "a+")
        k.write("\nInitial_f_sites: register_f_sites fails\n")
        k.close()
        sys.exit("register f error.")


if __name__ == "__main__":
    main()
