import datetime
import random
import string
import cgi
import psycopg2
from xml.dom.minidom import parseString
from flask import current_app, flash
from flask import Blueprint, redirect, render_template
from flask import request, url_for
from flask_user import current_user, login_required, roles_accepted
from flask_user.views import _get_safe_next_param, render, _send_registered_email, _endpoint_url, _do_login_user
from flask_user import signals
from webapp.models.user_models import MappingForm
from MappingCommon import MappingCommon

qual_blueprint = Blueprint('qual_blueprint', __name__)

# This is the employee qualification test page builder.
# The Employee submenu is accessible to authenticated users with the 'employee' role
@qual_blueprint.route('/employee/qualification', methods=['GET', 'POST'])
@roles_accepted('employee')
@login_required  # Limits access to authenticated users
def qualification():
    now = str(datetime.datetime.today())
    mapForm = MappingForm(request.form)

    mapc = MappingCommon()
    logFilePath = mapc.projectRoot + "/log"
    apiUrl = mapc.getConfiguration('APIUrl')
    kmlFrameHeight = mapc.getConfiguration('KMLFrameHeight')
    kmlFrameScript = mapc.getConfiguration('KMLFrameScript')
    hitAcceptThreshold = float(mapc.getConfiguration('HitI_AcceptThreshold'))
    qualTestTfTextStart = mapc.getConfiguration('QualTest_TF_TextStart')
    qualTestTfTextMiddle = mapc.getConfiguration('QualTest_TF_TextMiddle')
    qualTestTfTextEnd = mapc.getConfiguration('QualTest_TF_TextEnd')

    mapForm.kmlFrameHeight.data = kmlFrameHeight
    kmlFrameUrl = "%s/%s" % (apiUrl, kmlFrameScript)
    mapForm.kmlFrameUrl.data = kmlFrameUrl
    # Set submit path to be this script.
    submitTo = url_for('qual_blueprint.qualification')
    mapForm.submitTo.data = submitTo

    k = open(logFilePath + "/OL.log", "a")
    k.write("\nqualification: datetime = %s\n" % now)

    # Use the logged-in user's id as the worker id.
    cu = current_user
    workerId = cu.id

    # If this is a POST request, then save any worker maps, and check the mapping accuracy. 
    # Then either retry the KML or move on to next KML.
    if request.method == 'POST':
        kmlName = mapForm.kmlName.data
        assignmentId = mapForm.assignmentId.data
        tryNum = str(mapForm.tryNum.data)
        kmlData = mapForm.kmlData.data

        (kmlType, kmlTypeDescr) = mapc.getKmlType(kmlName)

        # Check if this is a re-POST as a result of a browser refresh.
        # Assignment should not be in the HITApproved status or have a mis-matched try count.
        mapc.cur.execute("select status, tries from qual_assignment_data where assignment_id = %s" % assignmentId)
        assignmentStatus, triesCur = mapc.cur.fetchone()
        if not (assignmentStatus == MappingCommon.HITApproved or triesCur > int(tryNum)):
            # If no kmlData, then no fields were mapped.
            if len(kmlData) == 0:
                k.write("qualification: OL reported 'save' without mappings for %s kml = %s\n" % (kmlTypeDescr, kmlName))
                k.write("qualification: Worker ID %s; training assignment ID = %s; try %s\n" % (workerId, assignmentId, tryNum))
                resultsSaved = True                 # Can't fail since no maps posted.
            else:
                k.write("qualification: OL saved mapping(s) for %s kml %s\n" % (kmlTypeDescr, kmlName))
                k.write("qualification: Worker ID %s; training assignment ID = %s; try %s\n" % (workerId, assignmentId, tryNum))

                # Save all drawn maps.
                resultsSaved = mapc.saveWorkerMaps(k, kmlData, workerId, assignmentId, tryNum)

            # If we have at least one valid mapping.
            if resultsSaved:
                # Post-process this worker's results.
                approved = mapc.trainingAssignmentSubmitted(k, assignmentId, tryNum, workerId, now, kmlName, kmlType)
                if approved:
                    mapForm.resultsAccepted.data = 1   # Indicate approved results.
                else:
                    mapForm.resultsAccepted.data = 2   # Indicate rejected results.
            else:
                mapForm.resultsAccepted.data = 3   # Indicate unsaved results.
        else:
            k.write("qualification: Worker refreshed their browser causing a re-POST. POST request ignored.\n")
            k.write("qualification: Worker ID %s; training assignment ID = %s; try %s\n" % (workerId, assignmentId, tryNum))

    # If GET request, tell showkml.js to not issue any alerts.
    else:
        mapForm.resultsAccepted.data = 0   # Indicate GET (i.e., no results alert in showkml)

    # Check if new or returning worker.
    qualified = mapc.querySingleValue("""select qualified from worker_data 
            where worker_id = '%s'""" % workerId)

    # First time for worker.
    if qualified is None:
        newWorker = True
        mapc.cur.execute("""INSERT INTO worker_data (worker_id, first_time, last_time) 
                VALUES ('%s', '%s', '%s')""" % (workerId, now, now))
        # Initialize number of training maps successfully completed.
        k.write("qualification: New training candidate %s (%s %s - %s) created.\n" % 
                (workerId, cu.first_name, cu.last_name, cu.email))
        doneCount = 0

    # Returning worker.
    else:
        # Check if worker already qualified.
        if qualified:
            k.write("qualification: Training candidate %s (%s %s - %s) has returned\nbut has already passed the qualification test. Notified and redirected.\n" % (workerId, cu.first_name, cu.last_name, cu.email))
            flash("You have already passed the qualification test. You may now map agricultural fields.")
            return redirect(url_for('main.employee_page'))

        newWorker = False
        mapc.cur.execute("""UPDATE worker_data SET last_time = '%s'
                WHERE worker_id = '%s'""" % (now, workerId))
        k.write("qualification: Training candidate %s (%s %s - %s) has returned.\n" % 
                (workerId, cu.first_name, cu.last_name, cu.email))

        # Calculate number of training maps worker has successfully completed.
        doneCount = int(mapc.querySingleValue("""select count(*) 
                from qual_assignment_data where worker_id = '%s'
                and (completion_time is not null and score >= %s)""" %
                (workerId, hitAcceptThreshold)))

    # Get total number of training maps to complete.
    totCount = int(mapc.querySingleValue("""select count(*) from kml_data 
        where kml_type = '%s'""" % MappingCommon.KmlTraining))

    # If worker is not done yet,
    if doneCount < totCount:
        # If worker's previous POST was unsaved, then present them with the same KML again.
        if mapForm.resultsAccepted.data == 3:
            k.write("qualification: Presenting worker %s with Unsaved %s kml %s again.\n" % 
                    (workerId, kmlTypeDescr, kmlName))
        else:
            # Or else, fetch the next training map for them to work on.
            kmlName = mapc.querySingleValue("""select name from kml_data
                left outer join 
                    (select * from qual_assignment_data where worker_id = '%s') qad 
                    using (name)
                where kml_type = '%s'
                    and (completion_time is null
                        or score < %s)
                order by gid
                limit 1""" % (workerId, MappingCommon.KmlTraining, hitAcceptThreshold))
            mapForm.kmlName.data = kmlName
            (kmlType, kmlTypeDescr) = mapc.getKmlType(kmlName)
            
            # Check the number of tries by this worker on this map.
            tries = mapc.querySingleValue("select tries from qual_assignment_data where worker_id = '%s' and name = '%s'" % (workerId, kmlName))

            # If no assignment for this KML, then worker is just starting the qual test,
            # or has successfully mapped the previous KML.
            if not tries:
                tries = 1
                mapc.cur.execute("""INSERT INTO qual_assignment_data 
                    (worker_id, name, tries, start_time, status) 
                    VALUES ('%s', '%s', %s, '%s', '%s') RETURNING assignment_id""" % (workerId, kmlName, tries, now, MappingCommon.HITAssigned))
                assignmentId = mapc.cur.fetchone()[0]
            # Else, the user tried and failed to successfully map the previous KML and must try again.
            elif request.method == 'POST':
                tries = int(tries) + 1
                mapc.cur.execute("""UPDATE qual_assignment_data SET tries = %s 
                    WHERE worker_id = '%s' and name = '%s' RETURNING assignment_id""" % 
                    (tries, workerId, kmlName))
                assignmentId = mapc.cur.fetchone()[0]
            # Or user has simply returned (via the menu or refresh) to continue to the test. 
            else:
                assignmentId = mapc.querySingleValue("""SELECT assignment_id FROM qual_assignment_data 
                    WHERE worker_id = '%s' and name = '%s'""" %
                    (workerId, kmlName))

            mapForm.tryNum.data = tries
            mapForm.assignmentId.data = assignmentId
            k.write("qualification: Candidate starting try %d on %s kml #%s: %s\n" % (tries, kmlTypeDescr, doneCount + 1, kmlName))

    # Worker is done with training. Record that fact.
    else:
        mapc.grantQualification(workerId, now)
        k.write("qualification: Training candidate %s (%s %s - %s) has passed the qualification test. Notified and redirected.\n" % 
                (workerId, cu.first_name, cu.last_name, cu.email))
        flash("Congratulations! You have passed the qualification test. You may now map agricultural fields.")
        return redirect(url_for('main.employee_page'))

    mapc.dbcon.commit()

    # Complete building the HTTP response.
    if newWorker:
        progressStatus = qualTestTfTextStart % { 'totCount': totCount }
    else:
        if doneCount < totCount:
            progressStatus = qualTestTfTextMiddle % { 'doneCount': doneCount, 'totCount': totCount }
        else:
            progressStatus = qualTestTfTextEnd % { 'totCount': totCount }
    mapForm.progressStatus.data = progressStatus

    del mapc
    k.close()

    # Pass GET/POST method last used for use by JS running the website menu.
    mapForm.reqMethod.data = request.method

    return render_template('pages/qualification_page.html', form=mapForm)
