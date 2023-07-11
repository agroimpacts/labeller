import datetime
import random
import string
import cgi
import psycopg2
from urllib import quote_plus
from flask import current_app, flash
from flask import Blueprint, redirect, render_template
from flask import request, url_for
from flask_user import current_user, login_required, roles_accepted
from flask_user.views import _get_safe_next_param, render, _send_registered_email, _endpoint_url, _do_login_user
from flask_user import signals
from webapp.models.user_models import MappingForm
from MappingCommon import MappingCommon

map_blueprint = Blueprint('map_blueprint', __name__)

# This is the employee agricultural fields mapping page builder.
# The Employee submenu is accessible to authenticated users with the 'employee' role
@map_blueprint.route('/employee/assignment', methods=['GET', 'POST'])
@roles_accepted('employee')
@login_required  # Limits access to authenticated users
def assignment():
    now = str(datetime.datetime.today())
    mapForm = MappingForm(request.form)

    mapc = MappingCommon()
    logFilePath = mapc.projectRoot + "/log"
    apiUrl = mapc.getConfiguration('APIUrl')
    kmlFrameHeight = mapc.getConfiguration('KMLFrameHeight')
    kmlFrameScript = mapc.getConfiguration('KMLFrameScript')
    #hitAcceptThreshold = float(mapc.getConfiguration('HitI_AcceptThreshold'))

    mapForm.kmlFrameHeight.data = kmlFrameHeight
    kmlFrameUrl = "%s/%s" % (apiUrl, kmlFrameScript)
    mapForm.kmlFrameUrl.data = kmlFrameUrl
    # Set submit path to be this script.
    submitTo = url_for('map_blueprint.assignment')
    mapForm.submitTo.data = submitTo

    k = open(logFilePath + "/OL.log", "a")
    k.write("\nassignment: datetime = %s\n" % now)

    # Use the logged-in user's id as the worker id.
    cu = current_user
    workerId = cu.id

    # If this is a POST request, then save any worker maps, and check the mapping accuracy. 
    # Then either retry the KML or move on to next KML.
    if request.method == 'POST':
        kmlName = mapForm.kmlName.data
        hitId = mapForm.hitId.data
        assignmentId = mapForm.assignmentId.data
        comment = mapForm.comment.data
        if len(comment) > 2048:
            comment = comment[:2048]
        savedMaps = mapForm.savedMaps.data
        kmlData = mapForm.kmlData.data

        (kmlType, kmlTypeDescr) = mapc.getKmlType(kmlName)

        # Check if this is a re-POST as a result of a browser refresh.
        # Assignment should be in the HITAssigned status.
        assignmentStatus = mapc.querySingleValue("select status from assignment_data where assignment_id = %s" % assignmentId)
        if assignmentStatus == MappingCommon.HITAssigned:
            # If worker saved their results...
            if savedMaps:
                # If no kmlData, then no fields were mapped.
                if len(kmlData) == 0:
                    k.write("assignment: OL reported 'save' without mappings for %s kml = %s\n" % (kmlTypeDescr, kmlName))
                    k.write("assignment: Worker ID %s, HIT ID = %s, Assignment ID = %s\n" % (workerId, hitId, assignmentId))
                    resultsSaved = True                 # Can't fail since no maps posted.
                else:
                    k.write("assignment: OL saved mapping(s) for %s kml = %s\n" % (kmlTypeDescr, kmlName))
                    k.write("assignment: Worker ID %s, HIT ID = %s, Assignment ID = %s\n" % (workerId, hitId, assignmentId))

                    # Save all drawn maps.
                    resultsSaved = mapc.saveWorkerMaps(k, kmlData, workerId, assignmentId)

                # If we have at least one valid mapping.
                if resultsSaved:
                    # Post-process this worker's results.
                    mapc.assignmentSubmitted(k, hitId, assignmentId, workerId, now, kmlName, kmlType, comment)
                    mapForm.resultsAccepted.data = 0   # Display no results alert in showkml
                else:
                    mapForm.resultsAccepted.data = 3   # Indicate unsaved results.

            # Else, worker returned the assigned KML.
            else:
                mapc.assignmentReturned(k, hitId, assignmentId, now, comment)
        else:
            k.write("assignment: Worker refreshed their browser causing a re-POST. POST request ignored.\n")
            k.write("assignment: Worker ID %s, HIT ID = %s, Assignment ID = %s\n" % (workerId, hitId, assignmentId))

    # If GET request, tell showkml.js to not issue any alerts.
    else:
        mapForm.resultsAccepted.data = 0   # Indicate GET (i.e., no results alert in showkml)

    # Check if new or returning worker.
    qualified = mapc.querySingleValue("""select qualified from worker_data where worker_id = '%s'""" % workerId)

    # Check if worker is qualified.
    if qualified is None or not qualified:
        k.write("assignment: Worker %s tried to map agricultural fields without passing the qualification test.\nNotified and redirected.\n" % workerId)
        flash("You have not passed the qualification test. You may not map agricultural fields. Please hover on the EMPLOYEE menu and click on 'View Training Video' and then 'Take Qualification Test'")
        return redirect(url_for('main.employee_page'))

    # Record the return of this worker.
    mapc.cur.execute("""UPDATE worker_data SET last_time = '%s'
            WHERE worker_id = '%s'""" % (now, workerId))
    k.write("assignment: Worker %s (%s %s - %s) has returned.\n" % 
            (workerId, cu.first_name, cu.last_name, cu.email))

    # If worker's previous POST was unsaved, then present them with the same KML again.
    if mapForm.resultsAccepted.data == 3:
        k.write("assignment: Presenting worker %s with Unsaved %s kml %s again.\n" % 
                (workerId, kmlTypeDescr, kmlName))
    else:
        # Or if this is the return of a worker with an assignment in Assigned state,
        # then present them with that KML.
        mapc.cur.execute("""SELECT name, hit_id, assignment_id FROM assignment_data
                INNER JOIN hit_data USING (hit_id)
                WHERE worker_id = '%s' AND status = '%s' LIMIT 1""" % 
                (workerId, MappingCommon.HITAssigned))
        row = mapc.cur.fetchone()
        mapc.dbcon.commit()
        if row is not None:
            kmlName = row[0]
            hitId = row[1]
            assignmentId = row[2]
            mapForm.kmlName.data = kmlName
            (kmlType, kmlTypeDescr) = mapc.getKmlType(kmlName)
            k.write("assignment: Presenting worker %s with Assigned %s kml %s again.\n" % 
                    (workerId, kmlTypeDescr, kmlName))
        # But if previous POST was saved or was GET for worker with no Assigned assignment,
        # then select a HIT from which to create a new assignment.
        else:
            # Get serialization lock.
            mapc.getSerializationLock()

            # Select the next KML for this worker: an Assignable HIT that this worker
            # has not yet been assigned to, and in random order.
            (hitId, kmlName) = mapc.getRandomAssignableHit(workerId)
            if hitId is None:
                # Release serialization lock.
                mapc.releaseSerializationLock()
                mapc.createAlertIssue("No available HITs in hit_data table",
                        """There are no HITs in the hit_data table that are available to worker %s\n
                        Ensure create_hit_daemon is running, and check its log file.""" % 
                        workerId)
                k.write("assignment: Worker %s tried to map agricultural fields but there were none to map.\nNotified and redirected.\n" % workerId)
                flash("We apologize, but there are currently no maps for you to work on. We are aware of the problem and will fix it as soon as possible. Please try again later.")
                return redirect(url_for('main.employee_page'))
            mapForm.kmlName.data = kmlName
            (kmlType, kmlTypeDescr) = mapc.getKmlType(kmlName)
                
            mapc.cur.execute("""INSERT INTO assignment_data 
                (hit_id, worker_id, start_time, status) 
                VALUES ('%s', '%s', '%s', '%s') RETURNING assignment_id""" % (hitId, workerId, now, MappingCommon.HITAssigned))
            assignmentId = mapc.cur.fetchone()[0]
            mapc.dbcon.commit()

            # Release serialization lock.
            mapc.releaseSerializationLock()

    mapForm.hitId.data = hitId
    mapForm.assignmentId.data = assignmentId
    k.write("assignment: Worker starting on %s kml %s\n" % (kmlTypeDescr, kmlName))

    del mapc
    k.close()

    # Pass GET/POST method last used for use by JS running the website menu.
    mapForm.reqMethod.data = request.method

    return render_template('pages/assignment_page.html', form=mapForm)
