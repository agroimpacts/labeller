import datetime
import random
import string
import cgi
import psycopg2
import subprocess
from distutils import util
from urllib import quote_plus
from flask import current_app, flash
from flask import Blueprint, redirect, render_template
from flask import request, url_for
from flask_user import current_user, login_required, roles_accepted
from flask_user.views import _get_safe_next_param, render, _send_registered_email, _endpoint_url, _do_login_user
from flask_user import signals
from webapp.models.user_models import HistoryForm
from webapp import csrf_protect
from MappingCommon import MappingCommon

hist_blueprint = Blueprint('hist_blueprint', __name__)
# *** NOTE: This exempts this blueprint from CSRF protection, when we only need to exempt the jQuery POST ***
# *** This did not appear to be working so I had to disable CSRF globally for the app ***
csrf_protect.exempt(hist_blueprint)

# This is the employee assignment history page builder.
# The Employee submenu is accessible to authenticated users with the 'employee' role
@hist_blueprint.route('/employee/assignment_history', methods=['GET', 'POST'])
@roles_accepted('employee')
@login_required  # Limits access to authenticated users
def assignment_history():
    now = str(datetime.datetime.today())
    histForm = HistoryForm(request.form)

    mapc = MappingCommon()
    logFilePath = mapc.projectRoot + "/log"

    # Set submit path to be this script.
    submitTo = url_for('hist_blueprint.assignment_history')
    histForm.submitTo.data = submitTo

    k = open(logFilePath + "/miscellaneous.log", "a")
    k.write("\nhistory: datetime = %s\n" % now)

    # Use the logged-in user's id as the worker id.
    cu = current_user
    workerId = cu.id

    githubIssue = mapc.getConfiguration("WI_GithubIssue")
    # Boolean config parameters are returned as string and need to be converted.
    githubIssue = bool(util.strtobool(githubIssue))

    # If this is a POST request, then handle worker inquiry or pagination request.
    if request.method == 'POST':
        # Handle worker inquiries here.
        if histForm.inquiryId.data is not None:
            k.write("worker inquiry: inquiryId (assignmentId) = %s\n" % histForm.inquiryId.data)
            k.write("worker inquiry: inquiryMessage = %s\n" % histForm.inquiryMessage.data)
            hitId = mapc.querySingleValue("SELECT hit_id FROM assignment_data WHERE assignment_id = %s" % 
                    histForm.inquiryId.data)
            kmlName = mapc.querySingleValue("SELECT name FROM hit_data WHERE hit_id = %s" % hitId)
	    serverName = mapc.serverName
	    url =  "https://%s/api/getkml?kmlName=%s&workerId=%s" % (serverName, kmlName, workerId)
            #url = subprocess.Popen(["Rscript", "%s/spatial/R/check_worker_assignment.R" % mapc.projectRoot, str(hitId), str(workerId), "N"], stdout=subprocess.PIPE).communicate()[0]
            #url = url.rstrip()
            if len(histForm.inquiryMessage.data) > 0:
                inquiryMessage = "Your inquiry message was:<br/>%s<br/><br/>" % histForm.inquiryMessage.data
            else:
                inquiryMessage = ""
            message = mapc.getConfiguration("WI_Message")
            inquiryResponse = "You inquired about site %s (HIT %s).<br/><br/>%s%s<br/><br/>Map URL: <a href='%s' target='_blank'>Map Comparison</a>" % \
                    (kmlName, hitId, inquiryMessage, message, url)
            if githubIssue:
                mapc.createIssue("Inquiry from worker %s: %s %s (%s)" % (workerId, cu.first_name, cu.last_name, cu.email), \
                        inquiryResponse, MappingCommon.WorkerInquiryIssue)
            return inquiryResponse

    # If no timeZone, then we must get that first.
    if histForm.timeZone.data is not None:
        prompt = mapc.getConfiguration("WI_Prompt")
        # Boolean config parameters are returned as string and need to be converted.
        prompt = bool(util.strtobool(prompt))
        if not githubIssue:
            prompt = False
        histForm.prompt.data = prompt

        # Otherwise, show N rows of history.
        mapc.cur.execute("""SELECT TO_CHAR(event_time at time zone '%s', 'DD Mon YYYY HH24:MI:SS'), 
                event_type, amount, feedback, assignment_id FROM assignment_history 
                WHERE event_type IN ('%s', '%s') AND worker_id = %s ORDER BY event_time DESC""" %
                (histForm.timeZone.data / 60, MappingCommon.EVTApprovedAssignment, \
                MappingCommon.EVTRejectedAssignment, workerId))
        histForm.assignmentData.data = mapc.cur.fetchall()

        mapc.cur.execute("""SELECT TO_CHAR(event_time at time zone '%s', 'DD Mon YYYY HH24:MI:SS'), 
                event_type, amount, feedback FROM assignment_history 
                WHERE event_type IN ('%s', '%s') AND worker_id = %s ORDER BY event_time DESC""" %
                (histForm.timeZone.data / 60, MappingCommon.EVTQualityBonus, MappingCommon.EVTTrainingBonus, workerId))
        histForm.bonusData.data = mapc.cur.fetchall()
        mapc.dbcon.commit()

        k.write("history: Worker requested history.\n")

    del mapc
    k.close()

    return render_template('pages/assignment_history_page.html', form=histForm)
