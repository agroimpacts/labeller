#! /usr/bin/python

import os
import pandas as pd
import boto3
import psycopg2
from datetime import datetime as DT
import numpy as np
from MappingCommon import MappingCommon

def add_sites_to_main(sites, bucket=None, kml_type=None, reset=False):
     
    """Gets grid sites from a csv and adds them to the main grid. 
    Adapts LLeiSong's register_f_sites and register_sites

    Arguments
    ---------
    sites : str
        File path or key of csv file containing names and type of sites to load.
        Can be on S3 or local. If on S3, provide the bucket. 
    bucket : str
        Name of S3 bucket containing sites
    kml_type : str
        Name of HIT type (e.g. "F", "E", or "N") or None (default)
    reset : bool
        Option to run function to reset database to previous state, removing 
        registered sites from kml_data and resetting avail in master_grid. 
	"""
    
    # database connection
    mapc = MappingCommon()
    log_file_path = mapc.projectRoot + "/log"

    # Set up logging
    ktype = kml_type if kml_type else "unnamed type"
	
    # Record start time
    log_hdr = "Registering " + ktype + "sites starting at " + \
        str(DT.now()) + os.linesep
    log = log_file_path + "/add_sites_to_main.log"  # log file name
    k = open(log, "a+")
    k.write(log_hdr)

    # load csv
    csv_name = os.path.basename(sites)
    if bucket and sites: 
        s3 = boto3.client('s3')
        obj = s3.get_object(Bucket=bucket, Key=sites)
        df = pd.read_csv(obj['Body'])
        print "Loading " + str(len(df)) + " from s3 file: " + \
            csv_name
    elif not bucket and sites:
        df = pd.read_csv(sites)
        print "Loading" + str(len(df)) + "from local file: " + \
            csv_name 
    else: 
        print("Please try again")
        
    nsites = str(len(df))

    k = open(log, "a+")
    log_msg = "Read in " + nsites + " " + ktype + " sites from " + \
        csv_name + os.linesep
    k.write(log_msg)
    k.close()

    # Get all site names or filter by type
    if kml_type:
        names = df["name"][df.avail == kml_type].to_list()
        df = df.query("name in @names").copy()
    else:
        names = df["name"].to_list()
    names_str = "({})".format(', '.join("'{}'".format(name) for name in names))
    
    # Option to reset database for testing - not tested
    if reset:
	print "Resetting"
        query = "delete from master_grid where name in name in {}"\
            .format(names_str)
        mapc.cur.execute(query)
        mapc.dbcon.commit()

    else:
        if len(df) > 0:
            print("Adding sites to main grid")
            added = 0
            exists = 0
            query = "insert into master_grid (id, x, y, name, fwts, " +\
		"avail, date) values (%s, %s, %s, %s, %s, %s, %s);"
            for _, row in df.iterrows():
                xy_tab = tuple(row)
                
                try: 
                    mapc.cur.execute(query, xy_tab)
                    mapc.dbcon.commit()
                    added += 1
                except psycopg2.DatabaseError, err:
                    mapc.cur.execute("ROLLBACK")  
                    mapc.dbcon.commit()
                    exists += 1

                    error = "Error: " + str(DT.now()) + " " + str(err)
                    k = open(log, "a+")
                    k.write(error + os.linesep)
                    k.close()

            log_msg = str(added) + " sites registered, " + str(exists) + \
                " already existing from " + nsites + " total sites at " + \
		str(DT.now()) + os.linesep + os.linesep
            k = open(log, "a+")
            k.write(log_msg)
            k.close()

    if mapc.dbcon.closed == 0:
        mapc.close()

def main():
    mapc = MappingCommon()
    params = mapc.parseYaml("config_add.yaml")
    add_sites_to_main(sites=params["sites"], bucket=params["bucket"], 
                      kml_type=params["kml_type"], 
                      reset=params["reset_initial"])

if __name__ == "__main__":
    main()
