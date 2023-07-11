#! /usr/bin/python
import sys
import time
from datetime import datetime
from MappingCommon import MappingCommon
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

mapc = MappingCommon()

# create log
logFilePath = mapc.projectRoot + "/log"
k = open(logFilePath + "/assignment_notification_daemon.log", "a+")
now = str(datetime.today())
k.write("\nassignment_notification: Daemon starting up at %s\n" % now)
k.close()

# workers = dict()
lastAssignableCount = dict()

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

while True:
    hitPollingInterval = int(mapc.getConfiguration('Hit_PollingInterval'))
    if(hitPollingInterval * 3 < 60):
        notificationInterval = hitPollingInterval * 3
    else:
        notificationInterval = 60
        
    sender = "no-reply@crowdmapper.org"
    receiver = mapc.getConfiguration('Hit_NotificationEmailAddress')

    k = open(logFilePath + "/assignment_notification_daemon.log", "a+")
    now = str(datetime.today())
    
    # Read worker_data
    # Get currently qualified workers and their information 
    sql = """SELECT worker_id, first_name, last_name, email, 
              qualified FROM users
              INNER JOIN worker_data ON users.id = worker_data.worker_id
              where qualified='True' ORDER BY worker_id ASC;
              """
    mapc.cur.execute(sql)
    worker_data = mapc.cur.fetchall()
    mapc.dbcon.commit()

    # Read in worker data to collect 
    for worker in worker_data:
        workerId = worker[0]
        workerName = worker[1] + " " + worker[2]
        workerEmail = worker[3]
        if workerId not in lastAssignableCount:
            lastAssignable = -1
        else:
            lastAssignable = lastAssignableCount[workerId]
        assignable = 0
        pending = 0
        assigned = 0
        
        # Loop through each each hit counting assignables, assigneds, pendings
        for hitId, hit in mapc.getHitInfo().iteritems():
            # check assignable F hits
            if hit['kmlType'] != MappingCommon.KmlFQAQC:
                continue

            # 'else' clause below is executed if no match on workerId.
            for asgmtId, asgmt in hit['assignments'].iteritems():
                if asgmt['workerId'] == workerId:
                    if asgmt['status'] == MappingCommon.HITAssigned:
                        assigned += 1
                    elif asgmt['status'] == MappingCommon.HITPending:
                        pending += 1
                    break
            else:
                if hit['assignmentsRemaining'] > 0:
                    assignable += 1

        lastAssignableCount[workerId] = assignable

        # notify
        
        # if worker has just 1 assignment left, log it
        if assignable == 1 and lastAssignable > 1:
            assignResults = ("worker %s: last assignable=%s; assignable=%s;" +  
                             "pending=%s; assigned=%s\n") % (workerId, 
                              lastAssignable, assignable, pending, assigned)
            message = (workerName + " has just " + str(assignable) + 
                       " assignable assignments on " + mapc.hostName + 
                       ". Of these, " + str(assigned) +
                       " are assigned and " + str(pending) + 
                       " are pending. Please keep mapping to finish until" +
                       " all assignments and pendings are cleared")
            subject = (workerName + " 1 assignable assignment on " + 
                       mapc.hostName)
            email_worker(message, subject, sender, receiver)

            k.write("\nOne remaining assignment: datetime = %s\n" % now)
            k.write("Worker %s (%s) notified on %s\n" %
                       (workerId, workerName, mapc.hostName))
            k.write(assignResults)

        # if worker has no assigned or pending assignments
        if pending == 0 and assigned == 0:
            # the first time no further assignable HITs are avaiable
            if lastAssignable <> 0 and assignable == 0:
                # tell them to map on a different instance
                message = (workerName + " has finished all" +
                          " assignments on " + mapc.hostName + ", and should " +  
                          " log in any other instance where there are " + 
                          " available assignments")
                subject = (workerName + " has 0 assignments left on " + 
                           mapc.hostName)
                email_worker(message, subject, sender, receiver)
                k.write("Finished assignments: datetime = %s\n" % now)
                k.write("Worker %s (%s) notified of 0 assignments on %s\n" %
                       (workerId, workerName, mapc.hostName))
        
        # if new HITs become avaiable and previously there were none assignable
        # (this includes cases where a worker might still have pending & assgnd)
        if assignable > 0 and lastAssignable <= 0: 
            message = (workerName + " has " + str(assignable) + 
                       " new assignments available for mapping on " + 
                       mapc.home)
            subject = (workerName + " has " + str(assignable) + 
                       " new assignments on " + mapc.hostName)
            email_worker(message, subject, sender, receiver)
            k.write("New Assignments: datetime = %s\n" % now)
            k.write("Worker %s (%s) notified of %s assignments on %s\n" %
                   (workerId, workerName, assignable, mapc.hostName))
          
        

        # Sleep for specified polling interval
    k.close()
    time.sleep(notificationInterval)

