# `labeller` Internal Design

This document (originally written by Dennis McRitchie) describes the `labeller` platform developed for the original [Mapping Africa](mappingafrica.princeton.edu) project, which was designed to work within the Mechanical Turk ecosystem. The design will undergo substantial revision as `labeller` is adapted to remove dependence on Mechanical Turk. 

`labeller` consists of daemons, webserver WSGI scripts, and HIT event notification scripts, all cooperating to move each worker HIT assignment through its life stages starting with HIT creation, going on to the collecting of mapped fields, and ending with the final deletion of the HIT.

## Daemons
There are 4 daemons that are involved in the subsystem, as described below.

### `create_hit_daemon.py`
This daemon creates all HITs based on a number of DB configuration parameters that govern the number, type (Q, F, N) and characteristics (e.g., number of assignments) of each HIT. It calculates the number of HITs to create during each polling interval by subtracting the number of Assignable HITs on Amazon Mechanical Turk (Mturk) from the number of HITs of that type that are to be made available to workers per the relevant DB parameters.
Each HIT is created based on an entry from the kml_data table. In the case of Q HITs, the Q KMLs are reused in a round-robin fashion. Each time a Q HIT is submitted, its KML becomes available for reuse. While Q HITs are always created with only one assignment apiece, in the case of F and N HITs, they are created with the number of assignments specified by the appropriate DB parameter, minus the existing mapped_count for that KML (see below). There is also a DB parameter for limiting the number of assignments to a value below the threshold set by Mturk for incurring a surcharge for multi-assignment HITs. If the system runs low on N KMLs, the KMLgenerate.R daemon runs to replenish it (see below).

The primary content of a HIT is known in Mturk parlance as an ExternalQuestion. In the case of the Mapping Africa subsystem, this external question is a URL that identifies a specific KML by name and causes getkml.wsgi to execute (see below). This results in a web frame being returned to the worker’s browser that executes showkml.js and displays the specified KML boundaries over a background of Google Maps satellite imagery.
This daemon is also responsible for doing sanity checking on the number and state of HITs recorded in the DB as compared to those created on Mturk.
It logs its activity to …/log/createHit.log.

### `KMLgenerate.R`
This daemon provides more N KMLs as needed for create_hit_daemon.py to use in order to create N HITs.

It logs its activity to …/log/KMLgenerate.log.

### `process_qualification_requests.py`
This daemon polls Mturk looking for requests by workers that completed the Mapping Africa qualification test. If it finds a request, it checks the provided Training ID to ensure that all training KMLs were mapped successfully, and if so grants the Mapping Africa qualification to the user.
Two back-door “Training IDs” have also been provided for: one for previously qualified workers that lost their qualification when the Mapping Africa qualification type is recreated using create_qualification_type.py; and one to provide the unconditional granting of the Mapping Africa qualification for testing purposes.

It logs its activity to …/log/processQualReqs.log.

### `cleanup_absent_worker.py`
This daemon looks for F and N assignments that have been left in the Pending state for longer than a configurable length of time. Pending assignments are left in that state until a worker has enough history to achieve a trust level. If a worker stops working on Mapping Africa HITs before achieving a trust level, their Pending assignments will stay in that state indefinitely, and their HITs can never be deleted. This in turn affects the subsystem’s ability to achieve multiple mappings of F KMLs, and prevents create_hit_daemon.py from achieving the desired balance of available HITs on Mturk.

It logs its activity to …/log/cleanupAbsentWorker.log.

## Webserver WSGI Scripts
There are 4 WSGI Python scripts that can be executed when an HTTP or HTTPS request is made to labeller.princeton.edu, or for testing, to sandbox.princeton.edu. sandbox.princeton.edu is a Linux virtual interface (with its own name and IP address) on labeller.princeton.edu, sharing the eth0 network interface, which is the server’s interface to the internet (see “/etc/sysconfig/network-scripts/ifcfg-eth0:1”). This means that HTTP(S) requests to either labeller.princeton.edu or sandbox.princeton.edu are routed to the same server (a VM in this case), and are differentiated by the Apache webserver by name and IP address. 

Apache has been configured to have two Virtual Hosts, one for labeller requests and one for sandbox requests. (See “/etc/httpd/conf.d/ssl.conf”.) Requests to labeller.princeton.edu are handled by a process created under user labeller, and requests to sandbox.princeton.edu are handled by a process created under user sandbox. The effective user name is then used to determine 1) the path to the Mapping Africa code and 2) the database name (e.g., in the MturkMappingAfrica.py constructor).

Each HTTP(S) request specifies the name of the script to execute as part of the URL (e.g., http://labeller.princeton.edu/api/getkml?kmlName=SA12345). Apache’s Virtual Host definition maps the URL’s function name (“getkml” in this case) to the path to the corresponding .wsgi file in the “api” subdirectory. The WSGI scripts are as follows:

All of the WSGI scripts in this section log their activity to …/log/OL.log.

### `getkml.wsgi`
This script creates the HTML frame that will display the square grid represented by the KML file whose name was passed by the URL’s kmlName parameter, as well as the underlying Google Maps satellite view. It then passes it back to the worker’s browser as an HTTP response. The logic handles both Mturk HIT-encapsulated KMLs and training KMLs.
The returned frame loads the …/OL/showkml.js JavaScript file and, immediately upon completion of page loading, invokes its init() function with 1) the details of the KML to display, 2) putkml.wsgi and postkml.wsgi URLs to execute upon completion, as well as 3) the assignment ID and worker ID of the HIT (or Training ID in the case of a training KML).
The getkml URL that causes this script to be executed is embedded in the MTurk HIT itself (as described in the create_hit_daemon.py section above) or, in the case of a training KML, is embedded by the trainingframe.wsgi script (see that section below).

### `putkml.wsgi`
This script is invoked from the worker’s browser by the showkml.js code (using the URL passed to the init() function) in the event that the worker submits the HIT (or the training KML) without mapping any fields.
In the case of a training KML, KMLAccuracyCheck.R is called here to get a score, and an HTTP code of 460 is returned to the worker’s browser in the event that the score is below threshold. This will cause the worker to have to try to map the same KML again.

### `postkml.wsgi`
This script is invoked from the worker’s browser by the showkml.js code (using the URL passed to the init() function) in the event that the worker submits the HIT (or the training KML) with one or more fields mapped.
The polygons representing mapped fields are passed to the script, which loops through them and stores them in the user_maps table (or in the case of a training KML, in the qual_user_maps table).
Again, in the case of a training KML, KMLAccuracyCheck.R is called here to get a score, and an HTTP code of 460 is returned to the worker’s browser in the event that the score is below threshold. This will cause the worker to have to try to map the same KML again.

### `trainingframe.wsgi`
This script creates the framework for allowing prospective workers take the Mapping Africa qualification test. This script mimics Mturk by creating an HTML frame below which the training KMLs are rendered. This is done by inserting a URL at the end of the HTML frame that identifies a specific KML by name and causes getkml.wsgi to execute (as described above). It also creates a training ID if needed, keeps track of the number of tries a worker has attempted for each training KML, and whether or not all the training KMLs have been completed successfully.

Each training KML submission causes this script to be re-executed until all training KMLs have been successfully mapped, at which point the Training ID is returned to the worker for them paste into a Mapping Africa qualification request created by create_qualification_type.py. This request will be processed by process_qualification_requests.py as described above.
HIT Event Notification scripts

These scripts serve to notify the Mapping Africa subsystem of the following Mturk HIT-related events: AssignmentSubmitted, AssignmentReturned, AssignmentAbandoned, HITExpired. These events are generated by Mturk as described in the “Life Stages of a HIT” section below.
All of the notification scripts in this section log their activity to …/log/notifications.log.

### `process_notifications.wsgi`
This script is no longer used. It supports a REST notifications via HTTP request for the above Mturk events. After parsing the REST request, it internally calls ProcessNotifications.py, which does the heavy lifting. Mturk has now discontinued this notification type, so the Mapping Africa subsystem now uses email notifications for this purpose (see below).

## Other scripts
### `process_notifications.py`
This script is called by the postfix email management subsystem on the labeller server. The postfix hook is configured by an entry in the /etc/aliases file: 
mturk_notification: "| /u/labeller/labeller/processmail/bin/processmail --user labeller --umask 007 --script /u/labeller/labeller/mturk/process_notifications.py"
This intercepts emails addressed to mturk_notification@labeller.princeton.edu. (There is a corresponding entry for mail addressed to mturk_sandbox_notification@labeller.princeton.edu.) The above “aliases” entry passes the email to processmail, which performs security checks to ensure that it is being called from postfix as user root, and then passes the email to process_notifications.py as the specified user (e.g., labeller) with the specified umask (e.g., 007).

Note that processmail needs to be rebuilt on a new server or if the mailer (e.g., postfix) is changed. This can be done by following the instructions in …/labeller/README.

After parsing the email body, `process_notifications.py`, like `process_notifications.wsgi`, calls `ProcessNotifications.py` to do the actual work.

### `ProcessNotifications.py`
This is a major component in the Mapping Africa subsystem in that it handles the end-of-life processing of each assignment and HIT. It collects the event-identifying information (e.g., HIT ID, Assignment ID, event time, etc) and then calls the appropriate event handler based on the event type.

1. AssignmentSubmitted Event:

    This is the most complex event handler. It calls `getAssignment()` to acquire the worker ID, the submit time, the special parameters passed by `showkml.js`, and the hitStatus. It then determines the KML type (Q, F, N) and calls either `QAQCSubmission()` (if Q type) or `NormalSubmission()` (if F or N type).

    `QAQCSubmission()` calls `KMLAccuracyCheck.R` for this assignment, and based on the results, adjusts the worker’s cumulative quality score and does other DB housekeeping. It also approves or rejects assignments on Mturk, pays training, difficulty and quality bonuses, and potentially revokes a worker’s qualification if their quality score drops too low. It then deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state. Finally, `NormalPostProcessing()` is called to potentially process any F or N assignments that are in the Pending state (see below). `NormalSubmission()` is called for F and N assignments, and approves the assignment on Mturk in all cases. It also checks the worker’s quality score to determine whether to mark an assignment as Approved, Untrusted, or Pending (if there is not enough history) in the assignment_data table. If the assignment is Approved, the mapped_count for the KML is incremented in the kml_data table. Finally it deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state.
    `NormalPostProcessing()` checks if the worker has enough history to have a trust level. If so, for each of the worker’s HIT assignments that are in the Pending state, marks it as either Approved or Untrusted (per the trust level) in the assignment_data table. It then deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state.

2. AssignmentReturned Event:
This event handler records the assignment as being Returned in the assignment_data table. It then deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state.

3. AssignmentAbandoned Event:
This event handler records the assignment as being Abandoned in the assignment_data table. It then deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state.

4. HITExpired Event:
This event handler records the HIT as being expired in the hit_data table. It then deletes the HIT on Mturk (and marks it as such in the hit_data table) if the HIT is in the Mturk Reviewable state and has no assignments in the Pending or Accepted state.


## Life Stages of a HIT
A HIT comes into existence when `create_hit_daemon.py` selects a KML from the kml_data table and encapsulates it in a Mturk CreateHIT request. The HIT can then be seen by Mturk workers, and HITs of this type can be accepted by any worker that has earned the Mapping Africa qualification by passing the qualification test described above.

Mapping Africa HITs that exist on the Mturk platform and are Assignable, are randomly assigned to workers. Each worker initially sees a fixed preview image (one of the training KMLs) in Preview mode to prevent workers being able to anonymously return an assigned HIT. Once the worker accepts the HIT assignment, the real image is displayed. The worker can then map any existing fields (per the training video) and submit the HIT assignment, or return the HIT assignment in order to be assigned a different HIT. The worker can also choose to do nothing, in which case, the HIT assignment will be flagged as abandoned after 24 hours.

If the worker submits the HIT assignment, either `putkml.wssgi` or `postkml.wsgi` will execute depending on whether no fields were mapped, or some fields were mapped (respectively). Mturk is then notified by `showkml.js` that the HIT has been submitted, after which Mturk sends a notification email to labeller.princeton.edu to mark the event. Mturk does the same for assignment return events, assignment abandonment events, and HIT expiration events (after 1 year, or after a HIT is explicitly expired using `expire_mturk_hits.py`).

Once a notification email event has been received as described above, it is processed, the worker is paid as appropriate, and the assignment_data table is updated with the HIT assignment’s new status. If all the HIT’s assignments have a final status (i.e., not Pending or Accepted), the HIT is also deleted on Mturk and marked as such in the hit_data table.

## Troubleshooting Through Logfile Tracing
When trying to troubleshoot a problem HIT or assignment (e.g., persists indefinitely on Mturk - per the list tool), searching through the logfiles can be very helpful to establish the life stages that the HIT or assignment traversed.

It is sometimes sufficient to search by assignment ID, but it is often more useful to search by its associated HIT ID as this will show you more information regarding both multi-assignment HITs, as well as single-assignment HITs that have been Accepted, Returned or Abandoned, and then Accepted again under a new assignment ID.

Also, note that not all events report all HIT-related information: e.g., PREVIEW events only report a HIT ID, but not assignment or worker ID. And AssignmentReturned and AssignmentAbandoned events provide the HIT and assignment IDs, but not the worker ID. In this latter case, looking for this assignment ID in OL.log will tell you the worker ID that accepted the HIT before returning or abandoning it.

It is usually helpful to search for a specific HIT ID in all log files: ‘grep <HIT_ID>  ~/labeller/log/*’.

Then the order of appearance for simple cases is: a creation event in createHit.log, followed by PREVIEW and ACCEPT requests in OL.log, followed by an AssignmentSubmitted event in notifications.log. However, in more complex cases where an assignment was returned or abandoned, the same KML under the same or different assignment ID will reappear in OL.log to be worked on by a different worker. This would then be followed by another submit, return, or abandonment event in notifications.log. Especially in these cases, it is necessary to look at the timestamps associated with all the events to develop a time trace of the order in which these actions happened.

Note: When looking at notifications.log timestamps, use the ‘event_time_str’ timestamp rather than the ‘notification arrived’ timestamp. Also, in some cases where the chain of events are back-to-back, you may wish to check the actual submit time of AssignmentSubmitted events that can be found in the completion_time field of the assignment_data table. This can be up to 30 seconds earlier than the event_time_str timestamp.

You should also be aware that even when an F KML has all of its assignments in a final state (i.e., not Pending or Accepted), it may reappear as a new HIT if any of the assignments were submitted by an untrusted worker. This can also happen if the maximum assignment count for a created HIT was artificially reduced by the Hit_MaxAssignmentsMT parameter to avoid a Mturk surcharge. In both cases the mapped_count has not reached the desired total, and a new HIT is required to allow this to happen.

In cases where developing a time trace of all the HIT-related events does not provide an explanation of what is going on, it may be necessary to search for the corresponding records in the hit_data, assignment_data, kml_data, and worker_data tables to further determine the state of affairs as understood by the Mapping Africa subsystem.

### Examples:

The example of the phantom HIT on Mturk was easy to find, since it does not appear in ANY logfile. In the case of the “missing getAssignment parameter” problem and “approveAssignment failed” error, the error itself appears in the notifications.log file. The errors may have actually been detected by erroneous field values in the assignment_data table, or by the fact that the HIT was never deleted when it should have been, because the event handler exited after logging the error and never completed its work. In any case, the notifications.log file identifies both the assignment ID that experienced the problem and the associated HIT ID. Grepping for the HIT ID in all log files reveals the creation of the HIT in createHit.log, and the assignment of the HIT to a worker in OL.log. In the case of these errors there may or may not be the usually subsequent putkml/postkml log entries in OL.log. Then in notifications.log, there is an abbreviated log report for this assignment ID: e.g.:

```
getnotifications: datetime = 2016-06-18 06:46:42.731086
getnotifications: notification arrived = 2016-06-18 06:46:42.425894
getnotifications: Email message parsed: True
ProcessNotifications: received 1 event(s):
ProcessNotifications: event_type = AssignmentSubmitted
ProcessNotifications: event_time_str = 2016-06-18 06:46:33
ProcessNotifications: hit_id = 3L2OEKSTW9A3HCBR5MR560EOM9UY8K
ProcessNotifications: assignmentId = 3WMOAN2SRBXA391KWFY65IW900DNVH
ProcessNotifications: workerId = AMUC6OI4A2GY4
ProcessNotifications: Missing getAssignment parameter(s) for assignment ID 3WMOAN2SRBXA391KWFY65IW900DNVH:
getnotifications: processing completed = 2016-06-18 06:46:42.843283
```


