#! /usr/bin/python

import os
import time
import smtplib
from datetime import datetime
from distutils import util
from MappingCommon import MappingCommon

#
# Main code begins here.
#
fqaqcIssueCount = 0
nqaqcIssueCount = 0

mapc = MappingCommon()

logFilePath = mapc.projectRoot + "/log"
k = open(logFilePath + "/createHit.log", "a+")

now = str(datetime.today())
k.write("\ncreateHit: Daemon starting up at %s\n" % now)
k.close()

# Execute loop based on polling interval
while True:
    hitPollingInterval = int(mapc.getConfiguration('Hit_PollingInterval'))
    hitStandAlone = mapc.getConfiguration('Hit_StandAlone')
    # Boolean config parameters are returned as string and need to be converted.
    hitStandAlone = bool(util.strtobool(hitStandAlone))
    Hit_AvailTarget = int(mapc.getConfiguration('Hit_AvailTarget'))
    hitReplacementThresholdF = float(mapc.getConfiguration('Hit_ReplacementThreshold_F'))
    hitReplacementThresholdN = float(mapc.getConfiguration('Hit_ReplacementThreshold_N'))
    hitAlertFrequency = int(mapc.getConfiguration('Hit_AlertFrequency')) * 60
    hitNeedFKmlsAlert = mapc.getConfiguration('Hit_NeedFKmlsAlert')
    # Boolean config parameters are returned as string and need to be converted.
    hitNeedFKmlsAlert = bool(util.strtobool(hitNeedFKmlsAlert))
    hitNeedNKmlsAlert = mapc.getConfiguration('Hit_NeedNKmlsAlert')
    # Boolean config parameters are returned as string and need to be converted.
    hitNeedNKmlsAlert = bool(util.strtobool(hitNeedNKmlsAlert))

    k = open(logFilePath + "/createHit.log", "a+")
    now = str(datetime.today())

    # Get serialization lock.
    mapc.getSerializationLock()

    # Get all Assignable HITs  and calculate our needs.
    numQaqcHits = 0
    numFqaqcHits = 0
    numNonQaqcHits = 0
    for hitId, row in mapc.getAssignableHitInfo().iteritems():
        # Calculate the number of assignable QAQC, FQAQC, and non-QAQC HITs 
        # currently available. For HITs with multiple assignments, only count HITs 
        # where the number of assignments created is less than the configured threshold.
        kmlType = row['kmlType']
        maxAssignments = row['maxAssignments']
        createdAssignments = maxAssignments - row['assignmentsRemaining']
        if kmlType == MappingCommon.KmlQAQC:
            numQaqcHits = numQaqcHits + 1
        elif kmlType == MappingCommon.KmlFQAQC:
            # Must have created less than the threshold number of assignments.
            threshold = max(int(round(hitReplacementThresholdF * maxAssignments)), 1)
            if createdAssignments < threshold:
                numFqaqcHits = numFqaqcHits + 1
        elif kmlType == MappingCommon.KmlNormal:
            # Must have created less than the threshold number of assignments.
            threshold = max(int(round(hitReplacementThresholdN * maxAssignments)), 1)
            if createdAssignments < threshold:
                numNonQaqcHits = numNonQaqcHits + 1

    # Create any needed QAQC HITs.
    kmlType = MappingCommon.KmlQAQC
    numReqdQaqcHits = max(Hit_AvailTarget - numQaqcHits, 0)
    if numReqdQaqcHits > 0:
        k.write("\ncreateHit: datetime = %s\n" % now)
        k.write("createHit: createHit sees %s Q HITs, and needs to create %s HITs\n" % 
            (numQaqcHits, numReqdQaqcHits))

    for i in xrange(numReqdQaqcHits):
        # Retrieve the last kml gid used to create a QAQC HIT.
        curQaqcGid = mapc.getSystemData('CurQaqcGid')

        # Select the next kml for which to create a HIT. 
        # Look for all kmls of the right type whose gid is greater than the last kml chosen.
        # Exclude any kmls that are currently associated with an active HIT.
        (nextKml, mappedCount, fwts, gid) = mapc.getAvailableKml(kmlType, 1, curQaqcGid)
        # If we have no kmls left, loop back to the beginning of the table.
        if nextKml is None:
            curQaqcGid = 0
            (nextKml, mappedCount, fwts, gid) = mapc.getAvailableKml(kmlType, 1, curQaqcGid)
            # If we still have no kmls left, all kmls are in use as HITs.
            # Try again later.
            if nextKml is None:
                break
        # Save the last kml gid used to create a QAQC HIT.
        mapc.setSystemData('CurQaqcGid', gid)

        # Create the QAQC HIT
        hitId = mapc.createHit(nextKml, fwts=fwts)
        k.write("createHit: Created HIT ID %s for Q KML %s\n" % (hitId, nextKml))

    # Create any needed FQAQC HITs.
    kmlType = MappingCommon.KmlFQAQC
    numReqdFqaqcHits = max(Hit_AvailTarget - numFqaqcHits, 0)
    if numReqdFqaqcHits > 0:
        k.write("\ncreateHit: datetime = %s\n" % now)
        k.write("createHit: createHit sees %s F HITs, and needs to create %s HITs\n" % 
            (numFqaqcHits, numReqdFqaqcHits))

    for i in xrange(numReqdFqaqcHits):
        # Select the next kml for which to create a HIT. 
        # Look for all kmls of the right type whose mapped count by a trusted worker is less than
        # the number of mappings specified by Hit_MaxAssignmentsF.
        # Exclude any kmls that are currently associated with an active HIT.
        hitMaxAssignmentsF = int(mapc.getConfiguration('Hit_MaxAssignmentsF'))
        (nextKml, mappedCount, fwts, gid) = mapc.getAvailableKml(kmlType, hitMaxAssignmentsF)
        # If we have no kmls left, all kmls in the kml_data table have been 
        # successfully processed. Notify Lyndon that more kmls are needed if we are in standalone mode.
        if nextKml is None:
            if (fqaqcIssueCount % (hitAlertFrequency / hitPollingInterval)) == 0:
                k.write("createHit: Alert: all F KMLs in kml_data table have been successfully processed. More KMLs needed to create more HITs of this type.\n")
                if hitStandAlone and hitNeedFKmlsAlert:
                    mapc.createAlertIssue("No F KMLs in kml_data table", 
                            "Alert: all F KMLs in kml_data table have been successfully processed. More KMLs needed to create more HITs of this type.")
            fqaqcIssueCount += 1
            break
        else:
            if (fqaqcIssueCount % (hitAlertFrequency / hitPollingInterval)) == 0:
                fqaqcIssueCount = 0
            else:
                fqaqcIssueCount += 1
        remainingAssignments = hitMaxAssignmentsF - mappedCount

        # Create the FQAQC HIT
        hitId = mapc.createHit(nextKml, fwts=fwts, maxAssignments=remainingAssignments)
        k.write("createHit: Created HIT ID %s with %d assignments for F KML %s\n" % 
                (hitId, remainingAssignments, nextKml))

    # Create any needed N HITs.
    kmlType = MappingCommon.KmlNormal
    numReqdNonQaqcHits = max(Hit_AvailTarget - numNonQaqcHits, 0)
    if numReqdNonQaqcHits > 0:
        k.write("\ncreateHit: datetime = %s\n" % now)
        k.write("createHit: createHit sees %s N HITs, and needs to create %s HITs\n" % 
            (numNonQaqcHits, numReqdNonQaqcHits))

    for i in xrange(numReqdNonQaqcHits):
        # Select the next kml for which to create a HIT. 
        # Look for all kmls of the right type whose mapped count by a trusted worker is less than
        # the number of mappings specified by Hit_MaxAssignmentsN.
        # Exclude any kmls that are currently associated with an active HIT.
        hitMaxAssignmentsN = int(mapc.getConfiguration('Hit_MaxAssignmentsN'))
        (nextKml, mappedCount, fwts, gid) = mapc.getAvailableKml(kmlType, hitMaxAssignmentsN)
        # If we have no kmls left, all kmls in the kml_data table have been 
        # successfully processed. Notify Lyndon that more kmls are needed.
        if nextKml is None:
            if (nqaqcIssueCount % (hitAlertFrequency / hitPollingInterval)) == 0:
                k.write("createHit: Alert: all N KMLs in kml_data table have been successfully processed. More KMLs needed to create more HITs of this type.\n")
                if hitNeedNKmlsAlert:
                    mapc.createAlertIssue("No N KMLs in kml_data table", 
                            "Alert: all N KMLs in kml_data table have been successfully processed. More KMLs needed to create more HITs of this type.")
            nqaqcIssueCount += 1
            break
        else:
            if (nqaqcIssueCount % (hitAlertFrequency / hitPollingInterval)) == 0:
                nqaqcIssueCount = 0
            else:
                nqaqcIssueCount += 1
        remainingAssignments = hitMaxAssignmentsN - mappedCount

        # Create the non-QAQC HIT
        hitId = mapc.createHit(nextKml, fwts=fwts, maxAssignments=remainingAssignments)
        k.write("createHit: Created HIT ID %s with %d assignments for N KML %s\n" % 
                (hitId, remainingAssignments, nextKml))

    # Release serialization lock.
    mapc.releaseSerializationLock()

    # Sleep for specified polling interval
    k.close()
    time.sleep(hitPollingInterval)
