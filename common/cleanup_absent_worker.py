#! /usr/bin/python

import os
import time
from datetime import datetime
from MappingCommon import MappingCommon

#
# Main code begins here.
#
mapc = MappingCommon()

logFilePath = mapc.projectRoot + "/log"
k = open(logFilePath + "/cleanupAbsentWorker.log", "a+")

now = str(datetime.today())
k.write("\ncleanupAbsentWorker: Daemon starting up at %s\n" % now)
k.close()

# Execute loop based on polling interval
while True:
    hitPollingInterval = int(mapc.getConfiguration('Hit_PollingInterval'))
    hitDuration = int(mapc.getConfiguration('Hit_Duration'))
    hitPendingAssignLimit = int(mapc.getConfiguration('Hit_PendingAssignLimit'))

    k = open(logFilePath + "/cleanupAbsentWorker.log", "a+")
    now = str(datetime.today())

    # Get serialization lock.
    mapc.getSerializationLock()

    # Commit the transaction just to refresh the value of localtimestamp below.
    mapc.dbcon.commit()

    # Search for all Assigned assignments that have been in that state longer than 
    # the permitted threshold.
    mapc.cur.execute("""select hit_id, assignment_id, worker_id, start_time 
        from assignment_data 
        where status = %s 
            and start_time + interval '%s seconds' < localtimestamp(0)
        order by completion_time""", 
        (MappingCommon.HITAssigned, hitDuration,))
    assignments = mapc.cur.fetchall()
    mapc.dbcon.commit()

    # If none then there's nothing to do for this polling cycle.
    timestamp = False
    if len(assignments) > 0:
        k.write("\ncleanupAbsentWorker: datetime = %s\n" % now)
        timestamp = True
        k.write("cleanupAbsentWorker: Checking for abandoned Assigned assignments: found %d\n" % 
                len(assignments))

        # Loop on all the abandoned Assigned assignments, and set their status to Abandoned;
        # then delete their associated HIT if appropriate.
        for assignment in assignments:
            hitId = assignment[0]
            assignmentId = assignment[1]
            workerId = assignment[2]
            startTime = assignment[3];

            k.write("\ncleanupAbsentWorker: Cleaning up Assigned assignmentId = %s\n" % assignmentId)
            k.write("cleanupAbsentWorker: Abandoned by workerId %s on %s\n" % 
                    (workerId, startTime))

            # Record the final QAQC, FQAQC or non-QAQC HIT status.
            assignmentStatus = MappingCommon.HITAbandoned
            mapc.cur.execute("""update assignment_data set status = '%s', completion_time = '%s'
                    where assignment_id = '%s'""" % (assignmentStatus, now, assignmentId))
            mapc.dbcon.commit()
            k.write("cleanupAbsentWorker: QAQC, FQAQC or non-QAQC assignment marked in DB as %s\n" %
                assignmentStatus.lower())

            # Delete the HIT if all assignments have been submitted and have a final status
            if mapc.deleteFinalizedHit(hitId, now):
                k.write("cleanupAbsentWorker: HIT %s has no remaining assignments and has been deleted\n" % hitId)
            else:
                k.write("cleanupAbsentWorker: HIT %s still has remaining turk Assigned or Pending assignments and cannot be deleted\n" % hitId)

    # Search for all Pending assignments that have been in that state longer than 
    # the permitted threshold.
    mapc.cur.execute("""select hit_id, assignment_id, worker_id, completion_time 
        from assignment_data 
        where status = %s 
            and completion_time + interval '%s seconds' < localtimestamp(0)
        order by completion_time""", 
        (MappingCommon.HITPending, hitPendingAssignLimit,))
    assignments = mapc.cur.fetchall()
    mapc.dbcon.commit()

    # If none then there's nothing to do for this polling cycle.
    if len(assignments) > 0:
        if not timestamp:
            k.write("\ncleanupAbsentWorker: datetime = %s\n" % now)
        k.write("cleanupAbsentWorker: Checking for abandoned Pending assignments: found %d\n" % 
                len(assignments))

        # Loop on all the abandoned Pending assignments, and set their status to Untrusted;
        # then delete their associated HIT if appropriate.
        for assignment in assignments:
            hitId = assignment[0]
            assignmentId = assignment[1]
            workerId = assignment[2]
            completionTime = assignment[3];

            k.write("\ncleanupAbsentWorker: Cleaning up Pending assignmentId = %s\n" % assignmentId)
            k.write("cleanupAbsentWorker: Abandoned by workerId %s on %s\n" % 
                    (workerId, completionTime))

            # Record the final FQAQC or non-QAQC HIT status.
            assignmentStatus = MappingCommon.HITUntrusted
            mapc.cur.execute("""update assignment_data set status = '%s' where assignment_id = '%s'""" %
                (assignmentStatus, assignmentId))
            mapc.dbcon.commit()
            k.write("cleanupAbsentWorker: FQAQC or non-QAQC assignment marked in DB as %s\n" %
                assignmentStatus.lower())

            # Delete the HIT if all assignments have been submitted and have a final status
            if mapc.deleteFinalizedHit(hitId, now):
                k.write("cleanupAbsentWorker: HIT %s has no remaining assignments and has been deleted\n" % hitId)
            else:
                k.write("cleanupAbsentWorker: HIT %s still has remaining turk Assigned or Pending assignments and cannot be deleted\n" % hitId)

    # Release serialization lock.
    mapc.releaseSerializationLock()

    # Sleep for specified polling interval
    k.close()
    time.sleep(hitPollingInterval)
