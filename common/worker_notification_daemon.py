#! /usr/bin/python

## Author: Lyndon Estes and Lei Song
## To send slack message for the workers about the mapping progress
## Run it on instance: 
## nohup python -u ~/labeller/common/worker_notification_daemon.py &

import time
from datetime import datetime
from MappingCommon import MappingCommon
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import pandas as pd

mapc = MappingCommon()
params = mapc.parseYaml("config.yaml")
url = params['labeller']['slack_url']

# create log
logFilePath = mapc.projectRoot + "/log"
k = open(logFilePath + "/worker_notification_daemon.log", "a+")
now = str(datetime.today())
k.write("\nworker_notification: Daemon starting up at %s\n" % now)
k.close()


def email_worker(message, subject, sender, receiver):
    msg = MIMEMultipart('related')
    msg['Subject'] = subject
    msg['From'] = sender
    msg['To'] = receiver
    body = MIMEText(message)
    msg.attach(body)
    s = smtplib.SMTP('localhost')
    s.sendmail(sender, [receiver], msg.as_string())
    s.quit()


def message(df, message_start):
    df_to_list = []
    for index, row in df.iterrows():
        val = row["name"] + " (" + str(row["assignable"]) + ")"
        df_to_list.append(val)
    message_str = ", ".join(df_to_list)
    message = message_start + "\n" + message_str + "\n"
    return message


def send_message_to_slack(text, url):
    import requests
    import json

    post = {"text": "{0}".format(text)}

    try:
        url = url
        header = {"Content-type": "'application/json"}
        json_data = json.dumps(post)

        requests.post(url=url, data=json_data.encode('ascii'), headers=header)
    except Exception as em:
        print("EXCEPTION: " + str(em))


def getHitInfo(mapc):
    none_index = 0
    sql = """SELECT hit_id, name, kml_type, max_assignments, reward
                FROM hit_data
                FULL JOIN kml_data USING (name)
                WHERE delete_time IS null
                AND kml_type = 'F'"""
    mapc.cur.execute(sql)
    hits = {}
    for hit in mapc.cur.fetchall():
        if hit[0] is None:
            status = 'Assignable'
            hits["none" + str(none_index)] = {'kmlName': hit[1], 'kmlType': hit[2], 'maxAssignments': None,
                                              'reward': None, 'assignmentsAssigned': None,
                                              'assignmentsPending': None, 'assignmentsCompleted': None,
                                              'assignmentsRemaining': None, 'status': status,
                                              'assignments': None}
            none_index += 1
        else:
            assignments = {}
            assignmentsAssigned = 0
            assignmentsPending = 0
            assignmentsCompleted = 0
            for asgmtId, asgmt in mapc.getAssignments(hit[0]).iteritems():
                # Include all but Abandoned assignments.
                # NOTE: this ensures that workers won't be reassigned to this HIT again
                # regardless of status, unless they abandoned it earlier.
                if asgmt['status'] != mapc.HITAbandoned:
                    assignments[asgmtId] = asgmt

                    # Count Assigned, Pending, and completed assignments.
                    # 'completed' always includes Approved assignments, but for
                    # QAQC HITs, also includes Rejected and Unscored assignments;
                    # does not include Returned or Untrusted assignments.
                    if asgmt['status'] == mapc.HITAssigned:
                        assignmentsAssigned += 1
                    elif asgmt['status'] == mapc.HITPending:
                        assignmentsPending += 1
                    elif asgmt['status'] in \
                            (mapc.HITApproved, mapc.HITRejected, \
                             mapc.HITUnscored):
                        assignmentsCompleted += 1

            # Unassignable means that the sum of completed assignments,
            # already-assigned-but-not-completed assignments, and pending (completed
            # but not yet scored) assignments is equal to a HIT's max_assignments count.
            status = 'Unassignable'
            maxAssignments = hit[3]
            assignmentsRemaining = maxAssignments - \
                                   (assignmentsAssigned + assignmentsPending + assignmentsCompleted)
            if assignmentsRemaining > 0:
                status = 'Assignable'
            hits[hit[0]] = {'kmlName': hit[1], 'kmlType': hit[2], 'maxAssignments': maxAssignments,
                            'reward': hit[4], 'assignmentsAssigned': assignmentsAssigned,
                            'assignmentsPending': assignmentsPending, 'assignmentsCompleted': assignmentsCompleted,
                            'assignmentsRemaining': assignmentsRemaining, 'status': status,
                            'assignments': assignments}
    mapc.dbcon.commit()
    return hits


def hit_counts(mapc, worker):
    assignable = 0
    pending = 0
    assigned = 0
    for hitId, hit in getHitInfo(mapc).iteritems():
        if not isinstance(hitId, str):
            # check assignable F hits
            if hit['kmlType'] == MappingCommon.KmlFQAQC:
                if hit['assignments'] != {}:
                    for asgmtId, asgmt in hit['assignments'].iteritems():
                        if asgmt['workerId'] == worker:
                            if asgmt['status'] == MappingCommon.HITAssigned:
                                assigned += 1
                            elif asgmt['status'] == MappingCommon.HITPending:
                                pending += 1
                        elif hit['assignmentsRemaining'] > 0:
                            assignable += 1
                elif hit['assignmentsRemaining'] > 0:
                    assignable += 1

        else:
            assignable += 1

    hit_counts = (worker, assigned, pending, assignable)
    return hit_counts


def get_worker_data(mapc):
    # fetch data
    sql = """SELECT worker_id, first_name, last_name, qualified FROM users 
                INNER JOIN worker_data ON users.id = worker_data.worker_id 
                WHERE qualified='True' 
                AND worker_id IN (select worker_id from assignment_data) 
                ORDER BY worker_id ASC;"""
    mapc.cur.execute(sql)
    workerlist = mapc.cur.fetchall()
    mapc.dbcon.commit()

    # Create worker dataframe initialized with empty values
    name_filter = params['labeller']['notification_filter']
    workers = pd.DataFrame.from_records(workerlist)
    if not workers.empty:
        workers = workers[~workers[2].isin(name_filter)]
        workers["name"] = workers[1] + " " + workers[2]
        workers = workers.iloc[:, [0, 4]]
        workers.columns = ["id", "name"]
    workers[['assigned', 'pending', 'assignable', 'lastassignable']] = \
        pd.DataFrame([[-1, -1, -1, -1]], index=workers.index)
    return workers

# initial dataframe to catch last iterations assignable values
workers_last = pd.DataFrame(columns=["id", "lastassignable"])
initial = True
workers_finish = []

# while loop starts here
while True:
    sender = "no-reply@crowdmapper.org"
    receiver = mapc.getConfiguration('Hit_NotificationEmailAddress')
    # receiver = "lyndon.estes@gmail.com"

    # get worker data
    workers = get_worker_data(mapc)
    
    if not workers.empty:
        # Read worker hits and classify HIT types
        for index, worker in workers.iterrows():
            # get hit/assignment data and update values
            workerid = worker["id"]
            hit_data = hit_counts(mapc, workerid)
            workers.at[index, ['assigned', 'pending', 'assignable']] = hit_data[1:]

            # if worker doesn't exist, add -1 to lastassignable and append worker
            # record if does, update lastassignable from workers_last data
            if workerid not in workers_last["id"].values:
                workers.at[index, "lastassignable"] = -1
                workers_last = workers_last.append({"id": workerid,
                                                    "lastassignable": -1},
                                                   ignore_index=True)
            else:
                lastval = workers_last[workers_last.id == workerid]["lastassignable"]
                workers.at[index, "lastassignable"] = lastval
                workers_last.at[workers_last.id == workerid, "lastassignable"] = hit_data[3]

        # set up monitoring dataframes
        # oneleft = workers.query("assignable == 1 and lastassignable > 1")
        zeroleft = workers.query("pending == 0 and assigned == 0 and \
                                 lastassignable >= 0 and assignable == 0")
        newhits = workers.query("assignable > 0 and lastassignable <= 0")
        zeroleft = zeroleft[~zeroleft.id.isin(workers_finish)]

        # messages
        k = open(logFilePath + "/message_notification_daemon.log", "a+")
        now = str(datetime.today())

        if not zeroleft.empty and not initial:
            subject = "Workers with no remaining assignments on " + mapc.hostName
            msgpre = ("The following workers have 0 remaining assignments on " +
                      mapc.hostName + ", and should switch to a new instance: ")
            zeromsg = message(zeroleft, msgpre)
            # email_worker(zeromsg, subject, sender, receiver)
            send_message_to_slack(zeromsg, url=url)
            k.write("Completed assignments: datetime = %s\n" % now)
            k.write("Message sent: \n %s" % zeromsg)
            # Mark names from workers_last
            workers_finish = workers_finish + zeroleft['id'].tolist()

        if not newhits.empty and not initial:
            subject = "Workers with new assignments on " + mapc.hostName
            msgpre = "The following workers have new assignments on " + mapc.hostName
            newmsg = message(newhits, msgpre)
            # email_worker(newmsg, subject, sender, receiver)
            send_message_to_slack(newmsg, url=url)
            k.write("New Assignments: datetime = %s\n" % now)
            k.write("Message sent:\n %s" % newmsg)
            workers_finish = []
        initial = False
        k.close()  # Close log
    time.sleep(int(mapc.getConfiguration('FKMLCheckingInterval')))
