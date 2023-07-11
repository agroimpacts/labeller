#! /usr/bin/python

# A daemon which is used to watch the incoming fsites, generate consensus maps
# and trigger learner when all fsites have been processed
# Author: Su Ye, Lei Song

import csv
import os
import sys
import time
from datetime import datetime
import boto3
import boto3.session
import psycopg2
import register_f_sites
import run_cvml
from MappingCommon import MappingCommon
from botocore.config import Config
import subprocess

# the below is for debugging under SuYe's project root
# mapc = MappingCommon(projectRoot='/home/sye/labeller/')
# mapc = MappingCommon('/media/su/DataFactory/MappingAfrica/labeller')

mapc = MappingCommon()

logFilePath = mapc.projectRoot + "/log"
k = open(logFilePath + "/generateConsensus.log", "a+")

# daemon start
now = str(datetime.today())
k.write("\ngenerateConsensus: Daemon starting up at %s\n" % now)
k.close()

# record the ongoing iteration time in the daemon, and initial iteration is 0
iteration_counter = int(mapc.getSystemData('IterationCounter'))

# stopping criterion 1: maximum iteration
maximum_iteration = int(mapc.getConfiguration('StoppingFunc_MaxIterations'))

# stopping criterion 2.2: gain threshold per iteration
accgain_threshold = float(mapc.getConfiguration('StoppingFunc_AccGainThres'))

# stopping criterion 2.1: gain threshold per iteration
acc_threshold = float(mapc.getConfiguration('StoppingFunc_AccThres'))

n_success = 0
n_fail = 0
n_validate = 0
n_holdout = 0

# the accuracy gains for the last three iterations
lastfirst_accgain = 100
lastsecond_accgain = 100
lastthird_accgain = 100

# a boolean variable to monitor if the loop is finished
IsFinished = False
LabelFail = False

# Execute loop based on FKMLCheckingInterval
while True:

    # for initial iteration, query holdout, validate and training sites that
    # are not processed from incoming_names table
    if iteration_counter == 0:
        mapc.cur.execute("SELECT name, run, iteration, usage, iteration_time "
                         "FROM incoming_names "
                         "INNER JOIN iteration_metrics USING (run, iteration) "
                         "WHERE processed = false")
        fkml_row = mapc.cur.fetchall()
        mapc.dbcon.commit()
        n_failed = 0

    # if not initial iteration, query only train type
    else:
        mapc.cur.execute("SELECT name, run, iteration, usage, iteration_time "
                         "FROM incoming_names "
                         "INNER JOIN iteration_metrics USING (run, iteration) "
                         "WHERE processed = false and usage = 'train'")
        fkml_row = mapc.cur.fetchall()
        mapc.dbcon.commit()
        mapc.cur.execute("SELECT count(name) "
                         "FROM incoming_names "
                         "WHERE label = false and processed = true "
                         "and run = (select max(run) from incoming_names)")
        n_failed = mapc.cur.fetchone()[0]
        mapc.dbcon.commit()

    n_notprocessed = len(fkml_row)
    index_name = 0
    index_run = 1
    index_iteration = 2
    index_usage = 3
    index_iteration_time = 4

    if n_failed > 0:
        mapc.cur.execute("SELECT name, run, iteration, usage, iteration_time "
                         "FROM incoming_names "
                         "INNER JOIN iteration_metrics USING (run, iteration) "
                         "WHERE label = false and processed = true and "
                         "run = (select max(run) from incoming_names)")
        ffkml_row = mapc.cur.fetchall()
        mapc.dbcon.commit()
        fn_notprocessed = len(ffkml_row)
        fn_fail = 0

        for i in range(fn_notprocessed):

            mapc.cur.execute("SELECT name, mapped_count, mappers_needed "
                             "FROM kml_data WHERE kml_type = '%s' and name = '%s'"
                             % (mapc.KmlFQAQC, ffkml_row[i][index_name]))
            kmldata_row = mapc.cur.fetchall()
            mapc.dbcon.commit()
            index_mappedcount = 1
            index_mappersneeded = 2

            # check if not processed kmls has enough mappers
            if kmldata_row[0][index_mappersneeded] is not None and \
                    kmldata_row[0][index_mappedcount] == kmldata_row[0][index_mappersneeded]:

                # if the kml has enough mappers, call consensus generation
                k = open(logFilePath + "/generateConsensus.log", "a+")
                if mapc.generateConsensusMap(k=k,
                                             kmlName=kmldata_row[0][index_name],
                                             kmlusage=ffkml_row[i][index_usage]):
                    try:
                        mapc.cur.execute("""update incoming_names set 
                                            label='TRUE' where name = '%s'""" % kmldata_row[0][index_name])
                        mapc.dbcon.commit()
                        k = open(logFilePath + "/generateConsensus.log", "a+")
                        k.write("\ngenerateConsensus: succeed to fix %s to save the label.\n" %
                                kmldata_row[0][index_name])
                        k.close()

                    except psycopg2.InternalError as e:
                        mapc.createAlertIssue("Database error",
                                              "generateConsensusDaemon: kml %s internal "
                                              "database error %s\n%s" %
                                              (kmldata_row[0][index_name],
                                               e.pgcode, e.pgerror))
                        exit(1)
                else:
                    fn_fail = fn_fail + 1

        if (fn_fail > 0) and (not LabelFail):
            LabelFail = True
            mapc.createAlertIssue("Failed labels",
                                  "generateConsensusDaemon: still %s incoming names "
                                  "have no label." % fn_fail)
        elif fn_fail == 0:
            LabelFail = False
            mapc.createAlertIssue("Fixed labels",
                                  "All failed incoming names have label now.")

    # check if any new incoming kmls that is not processed
    if n_notprocessed != 0:
        k = open(logFilePath + "/generateConsensus.log", "a+")

        it = iter(fkml_row)
        first = next(it)

        # check if run and iterations of incoming kml are identical
        if n_notprocessed != 1:
            if (all(first[index_run] == rest[index_run] and
                    first[index_iteration] == rest[index_iteration] for rest in
                    it) == False):
                mapc.createAlertIssue("Iterations of F kmls are not identical",
                                      "generateConsensusDaemon: runs or "
                                      "iterations of incoming F kmls "
                                      "for iteration_%s "
                                      "are not identical"
                                      % iteration_counter)
                exit(1)

        # check if it is a new iteration
        # if it is a new iteration, initialize counter variables
        if first[index_iteration] - iteration_counter == 1:
            n_success = 0
            n_fail = 0
            iteration_counter = iteration_counter + 1
            # Update the IterationCounter value in system_data table
            mapc.setSystemData('IterationCounter', iteration_counter)
            k = open(logFilePath + "/generateConsensus.log", "a+")
            k.write("\ngenerateConsensus: iteration_%s starting up at %s\n" %
                    (iteration_counter, first[index_iteration_time]))
            k.close()

        # check if the iteration of all kmls from learner is just greater than
        # iteration_counter by 1 when they are not equal
        if first[index_iteration] != iteration_counter and first[index_iteration] - iteration_counter != 1:
            mapc.createAlertIssue("Iterations of learner and labeller are not identical",
                                  "generateConsensusDaemon: learner outputs "
                                  "iterations_%s, but generate_consensus_daemon "
                                  "is awaiting for iterations_%s"
                                  % (first[index_iteration], iteration_counter + 1
                                     ))

        # record kmls that are actually processed among kml to be processed
        # for this processing time
        n_processed = 0

        for i in range(n_notprocessed):

            mapc.cur.execute("SELECT name, mapped_count, mappers_needed "
                             "FROM kml_data WHERE kml_type = '%s' and name = '%s'"
                             % (mapc.KmlFQAQC, fkml_row[i][index_name]))
            kmldata_row = mapc.cur.fetchall()
            mapc.dbcon.commit()
            index_mappedcount = 1
            index_mappersneeded = 2

            # check if kml has been successfully retrieved from kml_data
            if len(kmldata_row) == 0:
                mapc.createAlertIssue("Consensus generation fails",
                                      "generateConsensusDaemon: fail to retrieve "
                                      "kml %s in the kml_data table"
                                      % fkml_row[i][index_name])

            # check if not processed kmls has enough mappers
            if kmldata_row[0][index_mappersneeded] is not None and \
                    kmldata_row[0][index_mappedcount] == kmldata_row[0][index_mappersneeded]:

                # if the kml has enough mappers, call consensus generation
                if mapc.generateConsensusMap(k=k,
                                             kmlName=kmldata_row[0][index_name],
                                             kmlusage=fkml_row[i][index_usage]):
                    # The below is when highest score map is used for generating consensus for spatial collective
                    # if mapc.generateConsensusMap(k=k,
                    #                              kmlName=kmldata_row[0][index_name],
                    #                              kmlusage=fkml_row[i][index_usage],
                    #                              highestscore="TRUE"):
                    n_success = n_success + 1
                    try:
                        mapc.cur.execute("""update incoming_names set 
                                            label='TRUE' where name = '%s'""" % kmldata_row[0][index_name])
                        mapc.dbcon.commit()
                    except psycopg2.InternalError as e:
                        mapc.createAlertIssue("Database error",
                                              "generateConsensusDaemon: kml %s internal "
                                              "database error %s\n%s" %
                                              (kmldata_row[0][index_name],
                                               e.pgcode, e.pgerror))
                        exit(1)
                else:
                    n_fail = n_fail + 1
                    if fkml_row[i][index_usage] == 'holdout':
                        n_holdout = n_holdout + 1
                    elif fkml_row[i][index_usage] == 'validate':
                        n_validate = n_validate + 1

                n_processed = n_processed + 1

                # no matter success or failed, update processed in incoming_names
                # to be TRUE
                try:
                    mapc.cur.execute("""update incoming_names set 
                    processed='TRUE' where name = '%s'""" % kmldata_row[0][index_name])
                    mapc.dbcon.commit()

                except psycopg2.InternalError as e:
                    mapc.createAlertIssue("Database error",
                                          "generateConsensusDaemon: kml %s internal "
                                          "database error %s\n%s" %
                                          (kmldata_row[0][index_name],
                                           e.pgcode, e.pgerror))
                    exit(1)

        # when all fkml are processed, write processing info into log,
        # check stopping criteria, wake up learner, and call register_f_sites
        if n_processed == n_notprocessed:
            k = open(logFilePath + "/generateConsensus.log", "a+")
            k.write("\ngenerateConsensus: the iteration_%s has %s successful "
                    "and %s failed consensus creation\n" %
                    (iteration_counter, n_success, n_fail))
            k.write("\ngenerateConsensus: the iteration_%s finishing up at "
                    "%s\n" %
                    (iteration_counter, datetime.now()))
            k.close()
            if n_fail > 0:
                mapc.createAlertIssue("Generating label fails",
                                      "\ngenerateConsensusDaemon: %s incoming names "
                                      "fail to save label, including %s validate, %s holdout.\n" %
                                      (n_fail, n_validate, n_holdout))

            # output incoming_names to csv table
            mapc.cur.execute("""SELECT * From incoming_names """)
            incoming_rows = mapc.cur.fetchall()
            mapc.dbcon.commit()

            fieldnames = ['name', 'run', 'iteration', 'processed', 'usage', "label"]

            with open(logFilePath + "/incoming_names.csv", 'w') as csvOutput:
                csvOutputWriter = csv.DictWriter(csvOutput, fieldnames=fieldnames)
                csvOutputWriter.writeheader()
                for x in xrange(len(incoming_rows)):
                    csvOutputDic = {'name': incoming_rows[x][0], 'run': incoming_rows[x][1],
                                    'iteration': incoming_rows[x][2], 'processed': incoming_rows[x][3],
                                    'usage': incoming_rows[x][4], 'label': incoming_rows[x][5]}
                    csvOutputWriter.writerow(csvOutputDic)

            # Set up AWS and upload csv to /activermapper/planet
            params = mapc.parseYaml("config.yaml")
            aws_session = boto3.session.Session(aws_access_key_id=params['learner']['aws_access'],
                                                aws_secret_access_key=params['learner']['aws_secret'])

            s3_client = aws_session.client('s3', region_name=params['learner']['aws_region'])

            bucket = str(mapc.getConfiguration('S3BucketDir'))

            if params['labeller']['initial'] == 1:
                des_on_s3 = "planet/" + params['learner']['incoming_names_static']
                s3_client.upload_file(logFilePath + "/incoming_names.csv", bucket, des_on_s3)
                # remove tmp incoming_name.csv
                os.remove(logFilePath + "/incoming_names.csv")

                # Generate Github issue
                mapc.createAlertIssue("Finish initial drawing",
                                      "The initial drawing is finished.")
                sys.exit("The initial drawing is finished.")
            elif params['labeller']['initial'] == 2:
                # remove tmp incoming_name.csv
                os.remove(logFilePath + "/incoming_names.csv")
                # Generate Github issue
                mapc.createAlertIssue("Finish initial drawing",
                                      "The initial drawing is finished.")
                sys.exit("The initial independent drawing is finished.")
            else:
                des_on_s3 = params['learner']['prefix'] + "/" + params['learner']['incoming_names']

                s3_client.upload_file(logFilePath + "/incoming_names.csv", bucket, des_on_s3)

                # remove tmp incoming_name.csv
                os.remove(logFilePath + "/incoming_names.csv")

                # wake up learner
                id_cluster = run_cvml.main()
                if not not id_cluster:
                    k = open(logFilePath + "/generateConsensus.log", "a+")
                    k.write("\ngenerateConsensus: the iteration_%s triggering learner "
                            "succeed\n"
                            % iteration_counter)
                    k.close()
                else:
                    mapc.createAlertIssue("Fail to trigger learner",
                                          "\ngenerateConsensusDaemon: the iteration_%s "
                                          "fails in waking up learner\n" %
                                          iteration_counter)
                    k = open(logFilePath + "/generateConsensus.log", "a+")
                    k.write("\ngenerateConsensus: fail to trigger learner\n")
                    k.close()
                    break

                # call register_f_sites to generate F sites for the next
                # iteration
                config = Config(retries=dict(max_attempts=1000))  # Change the max of attempts for AWS
                while True:
                    emr_client = aws_session.client('emr',
                                                    region_name=params['learner']['aws_region'],
                                                    config=config)
                    emr_clusters = emr_client.list_clusters()

                    if emr_clusters["Clusters"]["Id" == id_cluster]["Status"]["State"] == "TERMINATED":
                        # criterion 1
                        if iteration_counter == maximum_iteration - 1:
                            IsFinished = True
                            break
                        else:
                            # query accuracy metrics when iteration times is at least 3
                            if iteration_counter > 1:
                                mapc.cur.execute("SELECT accuracy "
                                                 "FROM iteration_metrics WHERE iteration = %s"
                                                 % (iteration_counter + 1))
                                lastfirst_accgain = mapc.cur.fetchone()[0]
                                mapc.dbcon.commit()

                                mapc.cur.execute("SELECT accuracy "
                                                 "FROM iteration_metrics WHERE iteration = %s"
                                                 % iteration_counter)
                                lastsecond_accgain = mapc.cur.fetchone()[0]
                                mapc.dbcon.commit()

                                mapc.cur.execute("SELECT accuracy "
                                                 "FROM iteration_metrics WHERE iteration = %s"
                                                 % (iteration_counter - 1))
                                lastthird_accgain = mapc.cur.fetchone()[0]
                                mapc.dbcon.commit()

                                # criterion 2
                                if (lastfirst_accgain > acc_threshold and
                                    lastsecond_accgain > acc_threshold and
                                    lastthird_accgain > acc_threshold) and \
                                        (abs(lastfirst_accgain - lastsecond_accgain) < accgain_threshold and
                                         abs(lastsecond_accgain - lastthird_accgain) < accgain_threshold):
                                    IsFinished = True
                                    break

                        if register_f_sites.main():
                            k = open(logFilePath + "/generateConsensus.log", "a+")
                            k.write("\ngenerateConsensus: the iteration_%s register_f_sites "
                                    "succeed\n"
                                    % iteration_counter)
                            k.close()
                            mapc.createAlertIssue("New iteration finished",
                                                  "generateConsensus: the iteration_%s finished" %
                                                  iteration_counter)
                            LabelFail = False
                        else:
                            mapc.createAlertIssue("f sites generation fails",
                                                  "generateConsensus: the iteration_%s "
                                                  "register_f_sites fails" %
                                                  iteration_counter)
                            k = open(logFilePath + "/generateConsensus.log", "a+")
                            k.write("\ngenerateConsensus: for the iteration_%s, register_f_sites fails\n"
                                    % iteration_counter)
                            k.close()
                            sys.exit("Errors in register_f_sites")
                        break
                    time.sleep(10)

    # check if the active learning loop has been stopped
    if IsFinished:
        try:
            mapc.cur.execute("DELETE FROM incoming_names WHERE processed='FALSE'")
            mapc.dbcon.commit()
        except psycopg2.DatabaseError, err:
            print "Error in deleting incoming names from the last loop, rollback"
            mapc.cur.execute("ROLLBACK")
            mapc.dbcon.commit()
            k = open(logFilePath + "/generateConsensus.log", "a+")
            k.write(err + os.linesep)
            k.close()
            mapc.createAlertIssue("Error in deleting incoming names from the last loop",
                                  "generateConsensus: To delete the incoming name from the last iteration manually." +
                                  os.linesep + str(err))
        iteration_counter = iteration_counter + 1
        mapc.setSystemData('IterationCounter', iteration_counter)
        stop_daemons = subprocess.Popen("sleep 5; crontab -r ;" + mapc.projectRoot +
                                        "/common/daemonKiller.sh", shell=True)
        if stop_daemons:
            mapc.createAlertIssue("Iteration is stopped",
                                  "generateConsensus: iteration is stopped because of satisfactory result.")
            k = open(logFilePath + "/generateConsensus.log", "a+")
            k.write("\ngenerateConsensus: iteration is stopped because of satisfactory result.\n")
            k.close()
        else:
            mapc.createAlertIssue("Iteration is stopped but fails to stop daemons",
                                  "generateConsensus: iteration is stopped because of satisfactory result. But it "
                                  "fails to stop daemons")
            k = open(logFilePath + "/generateConsensus.log", "a+")
            k.write("\ngenerateConsensus: iteration is stopped because of satisfactory result. But it "
                    "fails to stop daemons\n")
            k.close()
        time.sleep(5)
        sys.exit("Iteration is stopped")

    # Sleep for specified checking interval
    time.sleep(int(mapc.getConfiguration('FKMLCheckingInterval')))
