import os
import pandas as pd
import boto3
import psycopg2
from datetime import datetime as DT
from MappingCommon import MappingCommon

def register_sites(sites, bucket=None, kml_type='F', reset=False):
    """
    Gets grid sites from a csv and registers them in kml_data. Adapts 
    @LLeiSong's register_f_sites for the simpler case of sites defined outside
    of labeller's database. Can handle different types of HITs

    Arguments
    ---------
    sites : str
        File path or key of csv file containing names and type of sites to load.
        Can be on S3 or local. If on S3, provide the bucket. 
    bucket : str
        Name of S3 bucket containing sites
    kml_type : str
        Name of HIT type (e.g. "F", "E", or "N")
    reset : bool
        Option to run function to reset database to previous state, removing 
        registered sites from kml_data and resetting avail in master_grid. 
    """
    
    # database connection
    mapc = MappingCommon()
    log_file_path = mapc.projectRoot + "/log"

    # Set up logging

    # Record start time
    log_hdr = "Registering " + kml_type + "sites starting at " + \
        str(DT.now()) + os.linesep
    log = log_file_path + "/generate_sites.log"  # log file name
    k = open(log, "a+")
    k.write(log_hdr)

    # load csv
    if bucket:
        s3 = boto3.client('s3')
        obj = s3.get_object(Bucket=bucket, Key=sites)
        df = pd.read_csv(obj['Body'])
    else:
        df = pd.read_csv(sites)          

    k = open(log, "a+")
    log_msg = "Read in " + kml_type  + " sites to register from " + \
	 sites + os.linesep
    k.write(log_msg)
    k.close()

#    except Exception as e: 
#        k = open(log, "a+")
#        k.write(sites + "not found or failed" + os.linesep)
#        k.close()

    # Filter sites that match kml_type
    names = df["name"][df.avail == kml_type].to_list()
    names_str = ', '.join("'{}'".format(name) for name in names)

    # Create database connection and query sites
    query = "select name from master_grid where name in ({}) and avail='T'"\
        .format(names_str)
    mapc.cur.execute(query)
    rows = mapc.cur.fetchall()

    # Option to reset database for testing
    if reset:
        query = "delete from kml_data where kml_type='{}'".format(kml_type);
        mapc.cur.execute(query)
        query = "update master_grid set avail='T' where name in ({})"\
            .format(names_str)
        mapc.cur.execute(query)
        mapc.dbcon.commit()

    else:
        if len(rows) > 0:
            try:
                for row in rows:
                    xy_tab = row + (kml_type, 0)
                    query = "insert into kml_data (name, kml_type, " +\
                        "mapped_count) values (%s, %s, %s);"
                    # print(query)
                    mapc.cur.execute(query, xy_tab)
                    mapc.dbcon.commit()

                query = "update master_grid set avail='{}' where name in ({})"\
                    .format(kml_type, names_str)
                mapc.cur.execute(query)

                log_msg = kml_type + "sites registered at " + str(DT.now()) +\
                    os.linesep
                k = open(log, "a+")
                k.write(log_msg)
                k.close()

            except psycopg2.DatabaseError, err:
                print "Error updating database: rolling back"
                mapc.cur.execute("ROLLBACK")  # In order to recover the database
                mapc.dbcon.commit()

                # Log message 
                error_log = log_file_path + "/sites_dbase_error.log"
                error = "Register sites error: " + str(DT.now()) + " " +\
                    str(err)
                k = open(error_log, "a+")
                k.write(error + os.linesep)
                k.close()

    if mapc.dbcon.closed == 0:
        mapc.close()

def main():
    mapc = MappingCommon()
    params = mapc.parseYaml("config.yaml")["labeller"]
    register_sites(sites=params["sites"], bucket=params["bucket"], 
                   kml_type=params["kml_type"], reset=params["reset_initial"])

if __name__ == "__main__":
    main()
