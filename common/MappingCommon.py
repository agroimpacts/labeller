import os
import sys
import subprocess
import socket
import pwd
import cgi
import json
import random
import pickle
from datetime import datetime
from dateutil import tz
from distutils import util
from xml.dom.minidom import parseString
import psycopg2
from psycopg2.extensions import adapt
import collections
from decimal import Decimal
from github import Github
from lock import lock
import yaml
import shapely
import geopandas as gpd

class MappingCommon(object):

    # HIT assignment_data.status constants

    # QAQC and non-QAQC HIT constants
    HITAssigned = 'Assigned'                    # HIT assigned to worker
    HITAbandoned = 'Abandoned'                  # HIT abandoned by worker
    HITReturned = 'Returned'                    # HIT returned by worker
    HITApproved = 'Approved'                    # HIT submitted and approved:
                                                # a) QAQC had high score
                                                # b) non-QAQC had high trust level
    # QAQC constants
    HITRejected = 'Rejected'                    # HIT submitted and rejected
    HITUnscored = 'Unscored'                    # HIT not scorable, hence approved
    HITReversed = 'Reversed'                    # HIT was originally rejected and then reversed.

    # non-QAQC constants (HIT always approved)
    HITPending = 'Pending'                      # Awaiting enough trust history to calculate trust level
    HITUntrusted = 'Untrusted'                  # Insufficiently high trust level
                                                # (non-QAQC KML reused in this case)

    # HIT status constants
    HITAssignable = 'Assignable'
    HITUnassignable = 'Unassignable'

    # KML kml_data.kml_type constants
    KmlNormal = 'N'                             # Normal (non-QAQC) KML
    KmlQAQC = 'Q'                               # QAQC KML
    KmlFQAQC = 'F'                              # FQAQC KML
    KmlTraining = 'I'                           # Initial training KML

    # HIT assignment_history.event_type constants
    EVTApprovedAssignment = 'Approved Assignment' # Assignment was approved
    EVTRejectedAssignment = 'Rejected Assignment' # Assignment was rejected
    EVTQualityBonus = 'Quality Bonus'           # Worker rewarded for high quality
    EVTTrainingBonus = 'Training Bonus'         # Worker rewarded for completing qualification test

    # Defined constants for GitHub issues
    AlertIssue = 'IssueAlertLabel'
    GeneralInquiryIssue = 'IssueGeneralInquiryLabel'
    WorkerInquiryIssue = 'IssueWorkerInquiryLabel'
    IssueTags = [(AlertIssue, 'IssueAlertAssignee'), 
                    (GeneralInquiryIssue, 'IssueGeneralInquiryAssignee'), 
                    (WorkerInquiryIssue, 'IssueWorkerInquiryAssignee')]
    
    # Database column name constants
    ScoresCol = 'scores'
    ReturnsCol = 'returns'

    # Serialization lock file name
    lockFile = 'serial_file.lck'

    def __init__(self, projectRoot=None):
        
        # Determine sandbox/mapper based on effective user name.
        self.euser = pwd.getpwuid(os.getuid()).pw_name
        self.home = os.environ['HOME']
        self.projectRoot = '%s/labeller' % self.home 
        self.hostName = socket.gethostname()
        self.shortHostName = self.hostName.split('.',1)[0]
        self.serverName = self.hostName
        if self.euser == 'mapper':
            self.mapper = True
        else:
            self.mapper = False
            if projectRoot is not None:
                self.projectRoot = projectRoot
            halves = self.serverName.split('.',1)
            ## this will have to be changed to allow this to work with dynamic
            # IPs
            self.serverName = '%s-sandbox.%s' % (halves[0], halves[1])

        params = self.parseYaml("config.yaml")

        db_production_name = params['labeller']['db_production_name']
        # db_sandbox_name = params['labeller']['db_sandbox_name']
        db_user = params['labeller']['db_username']
        db_password = params['labeller']['db_password']
        # GitHub user maphelp's token
        github_token = params['labeller']['github_token']
        github_repo = params['labeller']['github_repo']
        
        if self.mapper:
            self.db_name = db_production_name
        else:
            self.db_name = db_sandbox_name
        
        self.dbcon = psycopg2.connect("dbname=%s user=%s password=%s" % 
            (self.db_name, db_user, db_password))
        self.cur = self.dbcon.cursor()

        self.ghrepo = Github(github_token).get_repo(github_repo)

    def __del__(self):
        self.close()

    def close(self):
        self.dbcon.close()

    #
    # *** Utility Functions ***
    #

    # Parse yaml file of configuration parameters.
    def parseYaml(self, input_file):
        input_file = "%s/common/%s" % (self.projectRoot, input_file)
        with open(input_file, 'r') as yaml_file:
            params = yaml.load(yaml_file, Loader=yaml.FullLoader)
        return params

    # Retrieve a tunable parameter from the configuration table.
    def getConfiguration(self, key):
        self.cur.execute("select value from configuration where key = '%s'" % key)
        try:
            value = self.cur.fetchone()[0]
        except TypeError as e:
            if str(e).startswith("'NoneType'"):
                value = None
            else:
                raise
        self.dbcon.commit();
        return value

    # Retrieve a runtime parameter from the system_data table.
    def getSystemData(self, key):
        self.cur.execute("select value from system_data where key = '%s'" % key)
        try:
            value = self.cur.fetchone()[0]
        except TypeError as e:
            if str(e).startswith("'NoneType'"):
                value = None
            else:
                raise
        self.dbcon.commit();
        return value

    # Set a runtime parameter in the system_data table.
    def setSystemData(self, key, value):
        self.cur.execute("update system_data set value = '%s' where key = '%s'" % (value, key))
        self.dbcon.commit()

    # Obtain serialization lock to allow create_hit_daemon.py, cleanup_absent_worker.py, and 
    # individual ProcessNotifications.py threads to access Mturk and database records
    # without interfering with each other.
    def getSerializationLock(self):
        self.lock = lock('%s/common/%s' % (self.projectRoot, MappingCommon.lockFile))

    # Release serialization lock.
    def releaseSerializationLock(self):
        del self.lock

    # Request a single value from a single column of a table.
    # If there is no record that matches the select criteria, return None.
    def querySingleValue(self, sql):
        self.cur.execute(sql)
        try:
            value = self.cur.fetchone()[0]
        except TypeError as e:
            if str(e).startswith("'NoneType'"):
                value = None
            else:
                raise
        self.dbcon.commit();
        return value

    # Retrieve the KML type and its description for a  given KML name.
    def getKmlType(self, kmlName):
        self.cur.execute("select kml_type from kml_data where name = '%s'" % kmlName)
        kmlType = self.cur.fetchone()[0]
        self.dbcon.commit()
        if kmlType == MappingCommon.KmlQAQC:
            kmlTypeDescr = 'QAQC'
        elif kmlType == MappingCommon.KmlFQAQC:
            kmlTypeDescr = 'FQAQC'
        elif kmlType == MappingCommon.KmlNormal:
            kmlTypeDescr = 'non-QAQC'
        elif kmlType == MappingCommon.KmlTraining:
            kmlTypeDescr = 'training'
        return (kmlType, kmlTypeDescr)

    # Save and retrieve circular buffer into database.
    # NOTE: assumes that rightmost entry is most recent. 
    # Works well with collections.deque().
    # Store circular buffer array into specified column for specified worker.
    def putCB(self, array, dbField, workerId):
        self.cur.execute("update worker_data set %s=%s where worker_id = %s" % (dbField,'%s','%s'), (array,workerId,))
        self.dbcon.commit()

    # Retrieve circular buffer from specified column for specified worker.
    def getCB(self, dbField, workerId):
        self.cur.execute("select %s from worker_data where worker_id = %s" % (dbField,'%s'), (workerId,))
        cb = self.cur.fetchone()[0]
        self.dbcon.commit()
        return cb

    # Add new value to circular buffer for scores.
    def pushScore(self, workerId, value):
        depth = int(self.getConfiguration('Quality_ScoreHistDepth'))
        scores = self.getCB(self.ScoresCol, workerId)
        if scores is None:
            scores = collections.deque(maxlen=depth)
        else:
            scores = collections.deque(scores,maxlen=depth)
        scores.append(value)
        self.putCB(list(scores), self.ScoresCol, workerId)

    # Add new return state to circular buffer for returns.
    # State must be True for returns and False for submissions.
    def pushReturn(self, assignmentId, state):
        # Get the worker ID for this assignment.
        self.cur.execute("select worker_id from assignment_data where assignment_id = '%s'" % assignmentId)
        workerId = self.cur.fetchone()[0]
        self.dbcon.commit()
        depth = int(self.getConfiguration('Quality_ReturnHistDepth'))
        returns = self.getCB(self.ReturnsCol, workerId)
        if returns is None:
            returns = collections.deque(maxlen=depth)
        else:
            returns = collections.deque(returns,maxlen=depth)
        if state:
            value = 1.0
        else:
            value = 0.0
        returns.append(value)
        self.putCB(list(returns), self.ReturnsCol, workerId)

    # Get moving average of scores saved. If number of scores saved is 
    # less than the required depth, return None.
    def getAvgScore(self, workerId):
        depth = int(self.getConfiguration('Quality_ScoreHistDepth'))
        scores = collections.deque(self.getCB(self.ScoresCol, workerId),maxlen=depth)
        if len(scores) < depth:
            return None
        return sum(scores)/depth

    # Get moving average of scores saved. If number of scores saved is 
    # less than the required depth, return None.
    def getReturnRate(self, workerId):
        depth = int(self.getConfiguration('Quality_ReturnHistDepth'))
        returns = collections.deque(self.getCB(self.ReturnsCol, workerId),maxlen=depth)
        if len(returns) < depth:
            return None
        return sum(returns)/depth

    # Calculate quality score.
    def getQualityScore(self, workerId):
        weight = float(self.getConfiguration('Quality_ReturnWeight'))
        avgScore = self.getAvgScore(workerId)
        if avgScore is None:
            return None
        returnRate = self.getReturnRate(workerId)
        if returnRate is None:
            return None
        qScore = avgScore - (returnRate * weight)
        return qScore

    # Return True if worker is trusted based on quality score.
    def isWorkerTrusted(self, workerId):
        qualityScore = self.getQualityScore(workerId)
        if qualityScore is None:
            return None
        trustThreshold = float(self.getConfiguration('HitN_TrustThreshold'))
        if qualityScore >= trustThreshold:
            return True
        else:
            return False

    # Create a GitHub issue, specifying its title, body, and one of three
    #     predefined labels: MappingCommon.AlertIssue, MappingCommon.GeneralInquiryIssue, or
    #     MappingCommon.WorkerInquiryIssue
    def createIssue(self, title=None, body=None, label=None, sourcePrefix=True):
        for llabel, assignee in MappingCommon.IssueTags:
            if label == llabel:
                break
        else:
            assert False
        issueLabel = self.getConfiguration(llabel)
        issueAssignee = self.getConfiguration(assignee)
        if sourcePrefix:
            title = "%s@%s: %s" % (self.euser, self.shortHostName, title)
        self.ghrepo.create_issue(title=title, body=body, labels=[issueLabel], assignee=issueAssignee)
    
    # Create an Alert-type GitHub issue.
    def createAlertIssue(self, title=None, body=None, sourcePrefix=True):
        self.createIssue(title, body, MappingCommon.AlertIssue, sourcePrefix)

    # Build HTML SELECT tag with field category options.
    def buildSelect(self):
        select = '<select id="categLabel" title="Select a category for this field">\n'
        self.cur.execute("select category, categ_description, categ_default from categories order by sort_id")
        categories = self.cur.fetchall()
        self.dbcon.commit()
        for category in categories:
            categName = category[0]
            categDesc = category[1]
            if categDesc is None:
                categDesc = categName
            categDefault = category[2]
            if categDefault:
                categDefault = "selected='selected'"
            else:
                categDefault = ""
            select += "<option value='%s' %s>%s</option>\n" % (categName, categDefault, categDesc)
        select += "</select>\n"
        return select

    # Create grid json for specified KML name, and diameter
    def getGridJson(self, kmlName, dlon, dlat):
        # query database 
        self.cur.execute("""select x, y from kml_data inner join master_grid using (name) 
                where name = '%s'""" % kmlName)
        (lon, lat) = self.cur.fetchone()
        self.dbcon.commit()

        # get grid
        gf = gpd.GeoDataFrame({
            'lon': lon,
            'lat': lat
            }, index=[0])
        gf['center'] = gf.apply(lambda x: shapely.geometry.Point(x['lon'], x['lat']), axis=1)
        gf = gf.set_geometry('center')
        gf['center'] = gf['center'].buffer(1)
        gf['polygon'] = gf.apply(lambda x: shapely.affinity.scale(x['center'], dlon, dlat), axis=1)
        gf = gf.set_geometry('polygon')
        gf['grid'] = gf['polygon'].envelope	
        gjson = gf \
            .set_geometry('grid') \
            .filter(items=['grid']) \
            .to_json()
        return gjson

    # Get key and attributes for image serving
    def get_image_attributes(self):
        params = self.parseYaml("config.yaml")
        sentinelhub = params['labeller']['sentinelhub']
        # sentinelhub_config1 = params['labeller']['sentinelhub_cfg1']
        # sentinelhub_config2 = params['labeller']['sentinelhub_cfg2']
        # sentinelhub_config = params['labeller']['sentinelhub_config']
        bing_key = params['labeller']['bing_key']
        mapbox_key = params['labeller']['mapbox_key']

        return json.dumps(
            [sentinelhub, bing_key, mapbox_key]
        )
        # return [sentinelhub, bing_key, mapbox_key]

    #
    # *** HIT-Related Functions ***
    #

    # Return the KML count for a given type that can be used for creating a HIT.
    def getNumAvailableKml(self, kmlType, maxAssignments=1, gid=0):
        count = self.querySingleValue("""
            select count(k.gid)::int
            from kml_data k
            inner join master_grid using (name)
            where not exists (select true from hit_data h
                where h.name = k.name and delete_time is null)
            and  kml_type = '%s'
            and mapped_count < %s
            and k.gid > %s""" % (kmlType, maxAssignments, gid))
        return count

    # Return one KML that can be used for creating a HIT.
    def getAvailableKml(self, kmlType, maxAssignments=1, gid=0):
        # In SQL below, use mappers_needed column if not NULL.
        self.cur.execute("""
            select name, mapped_count, fwts, k.gid, mappers_needed
            from kml_data k
            inner join master_grid using (name)
            where not exists (select true from hit_data h
                where h.name = k.name and delete_time is null)
            and  kml_type = '%s'
            and ((mappers_needed is not null and mapped_count < mappers_needed)
                or  (mappers_needed is null and mapped_count < %s))
            and k.gid > %s
            order by k.gid
            limit 1""" % (kmlType, maxAssignments, gid))
        row = self.cur.fetchone()
        self.dbcon.commit()
        if row:
            kmlName = row[0]
            mappedCount = row[1]
            fwts = row[2]
            gid = row[3]
            mappersNeeded = row[4]
            # If 1st time processing this non-QAQC KML, then save the current max_assignments value.
            if mappersNeeded is None and kmlType != MappingCommon.KmlQAQC:
                self.cur.execute("update kml_data set mappers_needed = %s where name = %s", (maxAssignments, kmlName))
                self.dbcon.commit()
        else:
            kmlName = None
            mappedCount = None
            fwts = None
            gid = None
        return kmlName, mappedCount, fwts, gid

    # Return a HIT type based on specified probablilties.
    def getRandomHitType(self, workerId, hitStandAlone, fPresent=None):
        hitAvailTarget = int(self.getConfiguration('Hit_AvailTarget'))
        hitQaqcPercentage = int(self.getConfiguration('Hit_QaqcPercentage'))
        if hitStandAlone:
            hitFqaqcPercentage = int(self.getConfiguration('Hit_FqaqcPercentage'))

        # Get worker's random number generator state from DB, if present; else seed the generator.
        pstate = self.querySingleValue("select random_state from worker_data where worker_id = %s" % workerId)
        if pstate is None:
            random.seed(workerId)
        else:
            state = pickle.loads(pstate)
            random.setstate(state)
        # Get another pseudo-random number from generator.
        randInt = random.randint(0,99)
        # Store the new random state for this worker for next time.
        state = random.getstate()
        pstate = pickle.dumps(state)
        self.cur.execute("update worker_data set random_state = %s where worker_id = %s", (pstate, workerId))
        self.dbcon.commit()
            
        # calculate HIT type from random number.
        if randInt < hitQaqcPercentage:
            hitType = MappingCommon.KmlQAQC
        else:
            if hitStandAlone:
                if randInt < hitQaqcPercentage + hitFqaqcPercentage:
                    hitType = MappingCommon.KmlFQAQC
                else:
                    hitType = MappingCommon.KmlNormal
            else:
                if fPresent:
                    hitType = MappingCommon.KmlFQAQC
                else:
                    hitType = MappingCommon.KmlNormal
        return hitType

    # Return a random HIT that can be assigned to this worker.
    # NOTE: Assumes that getSerializationLock() has been called by the calling function.
    # NOTE: Achieves specified probabilities within 500 iterations.
    def getRandomAssignableHit(self, workerId):
        hitStandAlone = self.getConfiguration('Hit_StandAlone')
        # Boolean config parameters are returned as string and need to be converted.
        hitStandAlone = bool(util.strtobool(hitStandAlone))

        # Get all assignable HITs for this worker.
        hits = self.getAssignableHitInfo(workerId)
        if len(hits) == 0:
            return (None, None)

        # Select HITs of this type from those assignable to this worker.
        while True:
            # Are we in standlone mode?
            if hitStandAlone:
                # If so, get a standalone HIT type.
                hitType = self.getRandomHitType(workerId, hitStandAlone)
            else:
                # Else, check if any F HITs present and get a HIT type.
                fCount = len(dict((k, v) for k, v in hits.iteritems() if v['kmlType'] == MappingCommon.KmlFQAQC))
                #print fCount
                hitType = self.getRandomHitType(workerId, hitStandAlone, fCount > 0)
            #print "hitType: " + hitType

            tHits = dict((k, v) for k, v in hits.iteritems() if v['kmlType'] == hitType)
            if len(tHits) > 0:
                break
        #print tHits
            
        # If Q HIT, sort by age (oldest first).
        if hitType == MappingCommon.KmlQAQC:
            qSorted = sorted(tHits.iteritems())
            hit = qSorted[0]
        # Else, sort by assignments remaining (fewest first).
        else:
            oSorted = sorted(tHits.iteritems(), key=lambda(k,v): (v['assignmentsRemaining'],k))
            hit = oSorted[0]
        #print ''
        #print hit

        # Return hitId of 1st item and its kmlNname
        return hit[0], hit[1]['kmlName']

    # Return all HITs that are Assignable, and, if a workerId is specified, 
    # that has never been assigned to this worker.
    def getAssignableHitInfo(self, workerId=None):
        assignableHits = {}
        for hitId, hit in self.getHitInfo().iteritems():
            if hit['status'] == 'Assignable': 
                if workerId is None:
                    assignableHits[hitId] = hit
                else:
                    # 'else' clause below is executed if no match on workerId.
                    for asgmtId, asgmt in  hit['assignments'].iteritems():
                        if asgmt['workerId'] == workerId:
                            break
                    else:
                        assignableHits[hitId] = hit
        return assignableHits

    # Return one or all HITs created by the createHit() function.
    # Return all HITs if called without a hitId.
    def getHitInfo(self, hitId=None):
        sql = """SELECT hit_id, name, kml_type, max_assignments, reward
                FROM hit_data
                INNER JOIN kml_data USING (name)
                WHERE delete_time IS null"""
        if hitId is not None:
            sql += " AND hit_id = %s" % hitId
        self.cur.execute(sql)
        hits = {}
        assignments = {}
        for hit in self.cur.fetchall():
            assignments = {}
            assignmentsAssigned = 0
            assignmentsPending = 0
            assignmentsCompleted = 0
            for asgmtId, asgmt in self.getAssignments(hit[0]).iteritems():
                # Include all but Abandoned assignments.
                # NOTE: this ensures that workers won't be reassigned to this HIT again 
                # regardless of status, unless they abandoned it earlier.
                if asgmt['status'] != MappingCommon.HITAbandoned:
                    assignments[asgmtId] = asgmt

                    # Count Assigned, Pending, and completed assignments.
                    # 'completed' always includes Approved assignments, but for 
                    # QAQC HITs, also includes Rejected and Unscored assignments;
                    # does not include Returned or Untrusted assignments.
                    if asgmt['status'] == MappingCommon.HITAssigned:
                        assignmentsAssigned += 1
                    elif asgmt['status'] == MappingCommon.HITPending:
                        assignmentsPending += 1
                    elif asgmt['status'] in \
                            (MappingCommon.HITApproved, MappingCommon.HITRejected, \
                             MappingCommon.HITUnscored):
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
                    'assignments': assignments }
        self.dbcon.commit()
        if len(hits) == 0:
            return hits
        else:
            if hitId is not None:
                return hits[hitId]
            else:
                return hits

    # Retrieve all assignments for the specified HIT ID.
    def getAssignments(self, hitId):
        self.cur.execute("""
            select assignment_id, worker_id, completion_time, status
            from assignment_data
            where hit_id = '%s'
            """ % hitId)
        assignments = {}
        for asgmt in self.cur.fetchall():
            assignments[asgmt[0]] = {'workerId': asgmt[1], 'completionTime': asgmt[2], 'status': asgmt[3]}
        self.dbcon.commit()
        return assignments
    
    # Create json for woker feedback mode
    # with the 1st element as reference, and 2nd element as user maps
    def getFeedbackJson(self, name, workerId):
        # get assignment_id
        self.cur.execute("""select assignment_id 
	    from assignment_data 
	    inner join hit_data using (hit_id) 
            where name='%s' and worker_id=%s 
	    """ % (name, workerId))                                                                                               
        assignment_id = self.cur.fetchone()[0]                                                                                    
        self.dbcon.commit()                                                                                                  
    	# get qaqc                                                                                                           
        sql = "select geom_clean from qaqcfields where name='%s'" % name
        qaqc_json = gpd.read_postgis(sql, self.dbcon, geom_col='geom_clean', crs='epsg:4326') \
            .to_json()
        # get user maps
        sql = "select geom from user_maps where assignment_id=%d" %(assignment_id)
        user_json = gpd.read_postgis(sql, self.dbcon, geom_col='geom', crs='epsg:4326') \
            .to_json()
        return qaqc_json, user_json
 
    # Create a HIT for the specified KML ID.
    def createHit(self, kml=None, fwts=1, maxAssignments=1):
        self.fwts = int(fwts)
        duration = self.getConfiguration('Hit_Duration')
        reward = int(self.getConfiguration('Hit_Reward'))
        # Add the difficulty reward increment if KML's fwts > 1.
        self.hitRewardIncrement = Decimal(self.getConfiguration('Hit_RewardIncrement'))
        self.hitRewardIncrement2 = Decimal(self.getConfiguration('Hit_RewardIncrement2'))
        if self.fwts > 1:
            reward += int(round(self.hitRewardIncrement * (self.fwts - 1) + \
                self.hitRewardIncrement2 * (self.fwts - 1)**2, 2) * 100)

        now = str(datetime.today())
        self.cur.execute("""INSERT INTO hit_data 
                (name, create_time, max_assignments, duration, reward) 
                values ('%s', '%s', '%s', '%s', '%s')
                RETURNING hit_id""" % 
                (kml, now, maxAssignments, duration, reward))
        hitId = self.cur.fetchone()[0]
        self.dbcon.commit()
        return hitId

    # Delete HIT if it is Unassignable and it has no assignments in 
    # the Assigned or Pending state.
    def deleteFinalizedHit(self, hitId, submitTime):
        hit = self.getHitInfo(hitId)
        # If non-existent or previously deleted HIT.
        if hit is None:
            return None
        if hit['status'] == 'Unassignable' and \
                (hit['assignmentsAssigned'] + hit['assignmentsPending']) == 0:
            # Record the HIT deletion time.
            self.cur.execute("""UPDATE hit_data SET delete_time = '%s' 
                    WHERE hit_id = '%s'""" % (submitTime, hitId))
            self.dbcon.commit()
            return True
        else:
            return False

    #
    # *** Accuracy-Related Functions ***
    #

    # Score worker mapping of an 'I' or 'Q' KML.
    # Return floating point score (0.0-1.0), or None if could not be scored.
    def kmlAccuracyCheck(self, kmlType, kmlName, assignmentId, tryNum=None):
        if kmlType == MappingCommon.KmlTraining:
            scoreString = subprocess.Popen(["Rscript", "%s/spatial/R/KMLAccuracyCheck.R" % self.projectRoot, "tr", kmlName, str(assignmentId), str(tryNum)],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
        elif kmlType == MappingCommon.KmlQAQC:
            # Note: "None" must be passed as a string here.
            scoreString = subprocess.Popen(["Rscript", "%s/spatial/R/KMLAccuracyCheck.R" % self.projectRoot, "qa", kmlName, str(assignmentId), "None"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
        else:
            assert False
        try:
            score = float(scoreString)
            return score, scoreString
        except:
            return None, scoreString
        
    # generate ConsensusMap
    # Return true or false
    # Note: "FALSE" is a boolean value in R, different with False in python
    def generateConsensusMap(self, k, kmlName, kmlusage,highestscore="FALSE"):
        try:
           riskPixelPercentage = float(subprocess.Popen(["Rscript",
                                                "%s/spatial/R/consensus_map_generator.R" % self.projectRoot, kmlName, kmlusage, highestscore, "FALSE"],
                                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0])
        except Exception as e:
           k.write("generateConsensusMap fails for %s: \n %s \n" % (kmlName, e))  
           return False
        else:
           # using 10% as risk threshold for warning, if risky pixel percentage is larger
           # than 10% for a kml, the system will yield a warning (but won't stop)
           riskWarningThres = float(self.getConfiguration('Consensus_WarningThreshold'))
           if riskPixelPercentage is None:
               k.write(
                   "generateConsensusMap: consensus creation fails for %s\n" % kmlName)
               return False
           elif riskPixelPercentage > riskWarningThres:
               k.write("generateConsensusMap alerting: risky pixels in %s consensus "
                       "map has exceeded %s percentage threshold "
                       "(the kml consensus map has %s percentage risky pixels)\n" %
                       (kmlName, riskWarningThres * 100, riskPixelPercentage * 100))
               return True
           else:
               k.write(
                   "generateConsensusMap: consensus creation succeed for %s\n" %
                   kmlName)
               return True

    # Save all the worker's drawm maps.
    # Note: if tryNum is zero, then this is not a training case.
    def saveWorkerMaps(self, k, kmlData, workerId, assignmentId, tryNum=0):
        # Loop over every Polygon, and store its name and data in PostGIS DB.
        numGeom = 0
        numFail = 0
        errorString = ''
        k.write("saveWorkerMaps: kmlData = %s\n" % kmlData)
        kmlData = parseString(kmlData)
        for placemark in kmlData.getElementsByTagName('Placemark'):
            numGeom += 1
            # Get mapping name, type, and XML description.
            children = placemark.childNodes
            for child in children:
                # Process the extended data: category and category comments.
                if child.tagName == 'ExtendedData':
                    extData = child.childNodes
                    for node in extData:
                        name = node.getAttribute("name")
                        if name == 'category':
                            if node.getElementsByTagName("value")[0].firstChild is not None:
                                category = node.getElementsByTagName("value")[0].firstChild.data 
                            else:
                                category = ''
                        elif name == 'categ_comment':
                            if node.getElementsByTagName("value")[0].firstChild is not None:
                                categComment = node.getElementsByTagName("value")[0].firstChild.data 
                            else:
                                categComment = ''
                            if len(categComment) > 2048:
                                categComment = categComment[:2048]
                # Process the geometry name.
                elif child.tagName == 'name':
                    geomName = child.firstChild.data
                # We assume that any other child remaining is geometry.
                else:
                    geomType = child.tagName
                    geometry = child.toxml()

            k.write("saveWorkerMaps: Shape name = %s\n" % geomName)
            k.write("saveWorkerMaps: Shape type = %s\n" % geomType)
            k.write("saveWorkerMaps: Shape category = %s\n" % category)
            if len(categComment) > 0:
                k.write("saveWorkerMaps: Shape category comment = %s\n" % categComment)
            k.write("saveWorkerMaps: Shape KML = %s\n" % geometry)

            # Attempt to convert from KML to postgis geom format.
            try:
                # Report type and validity of this mapping.
                geomValue = self.querySingleValue("SELECT ST_IsValidDetail(ST_GeomFromKML('%s'))" % geometry)
                # ST_IsValidDetail returns with format '(t/f,"reason",geometry)'
                geomValid, geomReason, dummy = geomValue[1:-1].split(',')
                geomValid = (geomValid == 't')
                if geomValid:
                    k.write("saveWorkerMaps: Shape is a valid %s\n" % geomType)
                else:
                    k.write("saveWorkerMaps: Shape is an invalid %s due to '%s'\n" % (geomType, geomReason))
                now = str(datetime.today())
                if tryNum > 0:
                    self.cur.execute("""INSERT INTO qual_user_maps (name, geom, completion_time, 
                            category, categ_comment, assignment_id, try, geom_clean)
                            SELECT %s AS name, ST_GeomFromKML(%s) AS geom, %s AS datetime, 
                            %s AS category, %s AS categ_comment, %s AS assignment_id, %s AS try,
                            ST_MakeValid(ST_GeomFromKML(%s)) AS geom_clean""",
                            (geomName, geometry, now, category, categComment, assignmentId, tryNum, geometry))
                else:
                    self.cur.execute("""INSERT INTO user_maps (name, geom, completion_time, 
                            category, categ_comment, assignment_id, geom_clean)
                            SELECT %s AS name, ST_GeomFromKML(%s) AS geom, %s AS datetime, 
                            %s AS category, %s AS categ_comment, %s AS assignment_id, 
                            ST_MakeValid(ST_GeomFromKML(%s)) AS geom_clean""",
                            (geomName, geometry, now, category, categComment, assignmentId, geometry))
                self.dbcon.commit()
            except psycopg2.InternalError as e:
                numFail += 1
                self.dbcon.rollback()
                errorString += "\nKML mapping %s raised an internal datatase exception: %s\n%s%s\n" % (geomName, e.pgcode, e.pgerror, cgi.escape(geometry))
                k.write("saveWorkerMaps: Internal database error %s\n%s" % (e.pgcode, e.pgerror))
                k.write("saveWorkerMaps: Ignoring this mapping and continuing\n")
            except psycopg2.Error as e:
                numFail += 1
                self.dbcon.rollback()
                errorString += "\nKML mapping %s raised a general datatase exception: %s\n%s%s\n" % (geomName, e.pgcode, e.pgerror, cgi.escape(geometry))
                k.write("saveWorkerMaps: General database error %s\n%s" % (e.pgcode, e.pgerror))
                k.write("saveWorkerMaps: Ignoring this mapping and continuing\n")

        # If we have at least one invalid mapping.
        if numFail > 0:
            k.write("saveWorkerMaps: NOTE: %s mapping(s) out of %s were invalid\n" % (numFail, numGeom))
            if tryNum > 0:
                self.createAlertIssue("Database geometry problem",
                    "Worker ID = %s\nAssignment ID = %s; try %s\nNOTE: %s mapping(s) out of %s were invalid\n%s" %
                    (workerId, assignmentId, tryNum, numFail, numGeom, errorString))
            else:
                self.createAlertIssue("Database geometry problem",
                        "Worker ID = %s\nAssignment ID = %s\nNOTE: %s mapping(s) out of %s were invalid\n%s" % 
                        (workerId, assignmentId, numFail, numGeom, errorString))

        # If we have at least one valid mapping, return success.
        if numGeom > numFail:
            return True
        else:
            return False

    # Do post-processing for a training worker's submitted assignment.
    def trainingAssignmentSubmitted(self, k, assignmentId, tryNum, workerId, submitTime, kmlName, kmlType):
        assignmentStatus = None

        # Compute the worker's score on this KML.
        score, scoreString = self.kmlAccuracyCheck(MappingCommon.KmlTraining, kmlName, assignmentId, tryNum)
        # Reward the worker if we couldn't score his work properly.
        if score is None:
            assignmentStatus = MappingCommon.HITUnscored
            score = 1.          # Give new worker the max score
            approved = True
            k.write("qualification: Invalid value returned from R scoring script for:\nTraining KML %s, worker ID %s, assignment ID %s, try %s; assigning a score of %.2f\nReturned value:\n%s\n" %
                    (kmlName, workerId, assignmentId, tryNum, score, scoreString))
            self.createAlertIssue("KMLAccuracyCheck problem",
                    "Invalid value returned from R scoring script for:\nTraining KML %s, worker ID %s, assignment ID %s, try %s; assigning a score of %.2f\nReturned value:\n%s\n" %
                    (kmlName, workerId, assignmentId, tryNum, score, scoreString))

        # See if score exceeds the Accept threshold
        hitAcceptThreshold = float(self.getConfiguration('HitI_AcceptThreshold'))
        k.write("qualification: training assignment has been scored as: %.2f/%.2f\n" %
                (score, hitAcceptThreshold))

        if assignmentStatus is None:
            if score >= hitAcceptThreshold:
                assignmentStatus = MappingCommon.HITApproved
                approved = True
            else:
                assignmentStatus = MappingCommon.HITRejected
                approved = False

        # Record the assignment submission time and score (unless results were unsaved).
        now = str(datetime.today())
        self.cur.execute("""UPDATE qual_assignment_data SET completion_time = '%s', status = '%s',
            score = '%s' WHERE assignment_id = '%s'""" %
            (now, assignmentStatus, score, assignmentId))
        self.dbcon.commit()

        return approved

    # Do the  post-processing for a worker's returned assignment.
    def assignmentReturned(self, k, hitId, assignmentId, submitTime, comment):
        # Record the return in order to compute a return rate.
        self.pushReturn(assignmentId, True)

        # Mark the assignment as returned.
        self.cur.execute("""UPDATE assignment_data SET completion_time = '%s', status = '%s',
                comment = '%s' WHERE assignment_id = '%s'""" % 
                (submitTime, MappingCommon.HITReturned, comment, assignmentId))
        self.dbcon.commit()
        k.write("assignment: assignment %s has been marked as returned\n" % assignmentId)

        # Delete the HIT if all assignments have been submitted and have a final status
        # (i.e., there are no assignments in Pending or Assigned status).
        if self.deleteFinalizedHit(hitId, submitTime):
            k.write("assignment: hit %s has no remaining assignments and has been deleted\n" % hitId)
        else:
            k.write("assignment: hit %s still has remaining assigned or pending assignments and cannot be deleted\n" % hitId)


    # Do all post-processing for a worker's submitted assignment.
    def assignmentSubmitted(self, k, hitId, assignmentId, workerId, submitTime, kmlName, kmlType, comment):
        # Record the submission in order to compute a return rate.
        self.pushReturn(assignmentId, False)

        # If QAQC HIT, then score it and post-process any preceding FQAQC or non-QAQC HITs for this worker.
        if kmlType == MappingCommon.KmlQAQC:
            self.qaqcSubmission(k, hitId, assignmentId, workerId, submitTime, kmlName, kmlType, comment)
        # Else, if FQAQC HIT or non-QAQC HIT, then post-process it or mark it as pending post-processing.
        elif kmlType == MappingCommon.KmlNormal or kmlType == MappingCommon.KmlFQAQC:
            self.normalSubmission(k, hitId, assignmentId, workerId, submitTime, kmlName, kmlType, comment)

    def qaqcSubmission(self, k, hitId, assignmentId, workerId, submitTime, kmlName, kmlType, comment):
        assignmentStatus = None

        # Compute the worker's score on this KML.
        # NOTE: We used to call mapFix before calling KMLAccuracyCheck.
        score, scoreString = self.kmlAccuracyCheck(kmlType, kmlName, assignmentId)

        # Reward the worker if we couldn't score his work properly.
        if score is None:
            assignmentStatus = MappingCommon.HITUnscored
            score = self.getQualityScore(workerId)
            if score is None:
                score = 1.          # Give new worker the max score
            k.write("assignment: Invalid value returned from R scoring script for:\nQAQC KML %s, HIT ID %s, assignment ID %s, worker ID %s; assigning a score of %.2f\nReturned value:\n%s\n" % 
                    (kmlName, hitId, assignmentId, workerId, score, scoreString)) 
            self.createAlertIssue("KMLAccuracyCheck problem", 
                    "Invalid value returned from R scoring script for:\nQAQC KML %s, HIT ID %s, assignment ID %s, worker ID %s; assigning a score of %.2f\nReturned value:\n%s\n" %
                    (kmlName, hitId, assignmentId, workerId, score, scoreString))

        # Record score (actual or assumed) to compute moving average.
        self.pushScore(workerId, score)

        # Check if Mapping Africa qualification should be revoked
        # (needs to be done for both the approved and rejection cases because a worker may
        #  earn a quality score for the first time at the revocation level)
        if self.revokeQualificationIfUnqualifed(workerId, submitTime):
            k.write("assignment: Mapping Africa Qualification revoked from worker %s\n" % workerId)

        hitAcceptThreshold = float(self.getConfiguration('HitQ_AcceptThreshold'))
        hitNoWarningThreshold = float(self.getConfiguration('HitQ_NoWarningThreshold'))

        # If the worker's results could not be scored, or if their score meets 
        # the acceptance threshold, notify worker that his HIT was approved.
        if assignmentStatus is not None or score >= hitAcceptThreshold:
            # if score was above the no-warning threshold, then don't include a warning.
            warning = False
            if score < hitNoWarningThreshold:
                warning = True
            self.approveAssignment(workerId, assignmentId, submitTime, warning)
            if assignmentStatus is None:
                assignmentStatus = MappingCommon.HITApproved

            # Also, check if the worker merits a quality bonus for approved assignment.
            bonusStatus = self.payBonusIfQualified(workerId)
            if bonusStatus > 0:
                k.write("assignment: Accuracy bonus level %s paid to worker %s\n" % (bonusStatus, workerId))

        # Only if the worker's results were saved and scored, and their score did not meet 
        # the threshold do we reject the HIT.
        else:
            self.rejectAssignment(workerId, assignmentId, submitTime)
            assignmentStatus = MappingCommon.HITRejected

        # Record the assignment submission time and status, user comment, and score.
        self.cur.execute("""UPDATE assignment_data SET completion_time = '%s', status = '%s', 
            comment = %s, score = '%s' WHERE assignment_id = '%s'""" % 
            (submitTime, assignmentStatus, adapt(comment), score, assignmentId))
        self.dbcon.commit()
        k.write("assignment: QAQC assignment has been marked in DB as %s: %.2f/%.2f/%.2f\n" % 
            (assignmentStatus.lower(), score, hitAcceptThreshold, hitNoWarningThreshold))

        # Delete the HIT if all assignments have been submitted and have a final status
        # (i.e., there are no assignments in pending or assigned status).
        if self.deleteFinalizedHit(hitId, submitTime):
            k.write("assignment: QAQC hit has no remaining assignments and has been deleted\n")
        else:
            k.write("assignment: QAQC hit still has remaining assigned or pending assignments and cannot be deleted\n")

        # Post-process any pending FQAQC or non-QAQC HITs for this worker.
        self.NormalPostProcessing(k, workerId, submitTime)

    def normalSubmission(self, k, hitId, assignmentId, workerId, submitTime, kmlName, kmlType, comment):
        workerTrusted = self.isWorkerTrusted(workerId)
        if workerTrusted is None:
            # If not enough history, mark assignment as pending in order to save for post-processing.
            assignmentStatus = MappingCommon.HITPending
        elif workerTrusted:
            assignmentStatus = MappingCommon.HITApproved
            # Since results are trusted, mark this KML as mapped.
            self.cur.execute("UPDATE kml_data SET mapped_count = mapped_count + 1 WHERE name = '%s'" % kmlName)
            k.write("assignment: incremented mapped count by trusted worker for %s KML %s\n" % (kmlType, kmlName))
        else:
            assignmentStatus = MappingCommon.HITUntrusted

        # In all cases, notify worker that his HIT was approved.
        self.approveAssignment(workerId, assignmentId, submitTime)
        k.write("assignment: FQAQC or non-QAQC assignment has been approved and marked in DB as %s\n" % 
            assignmentStatus.lower())

        # Record the assignment submission time and status, and user comment.
        self.cur.execute("""UPDATE assignment_data SET completion_time = '%s', status = '%s', 
            comment = %s WHERE assignment_id = '%s'""" % 
            (submitTime, assignmentStatus, adapt(comment), assignmentId))
        self.dbcon.commit()

        # Delete the HIT if all assignments have been submitted and have a final status
        # (i.e., there are no assignments in pending or assigned status).
        if self.deleteFinalizedHit(hitId, submitTime):
            k.write("assignment: hit has no remaining assignments and has been deleted\n")
        else:
            k.write("assignment: hit still has remaining assigned or pending assignments and cannot be deleted\n")

    def NormalPostProcessing(self, k, workerId, submitTime):
        # Determine this worker's trust level.
        workerTrusted = self.isWorkerTrusted(workerId)
        if workerTrusted is None:
            k.write("assignment: Worker %s has insufficient history for evaluating FQAQC or non-QAQC HITs\n" %
                    workerId)
            return

        # Get the the key data for this worker's pending FQAQC or non-QAQC submitted HITs.
        self.cur.execute("""select name, assignment_id, hit_id
            from assignment_data inner join hit_data using (hit_id)
            where worker_id = %s and status = %s order by completion_time""", 
            (workerId, MappingCommon.HITPending,))
        assignments = self.cur.fetchall()
        self.dbcon.commit()

        # If none then there's nothing to do.
        if len(assignments) == 0:
            return

        k.write("assignment: Checking for pending FQAQC or non-QAQC assignments: found %d\n" % len(assignments))

        # Loop on all the pending FQAQC or non-QAQC HITs for this worker, and finalize their status.
        for assignment in assignments:
            kmlName = assignment[0]
            assignmentId = assignment[1]
            hitId = assignment[2]

            k.write("assignment: Post-processing assignmentId = %s\n" % assignmentId)

            # If the worker's results are reliable, we will mark the HIT as approved.
            if workerTrusted:
                assignmentStatus = MappingCommon.HITApproved

                # Since results trusted, mark this KML as mapped.
                self.cur.execute("update kml_data set mapped_count = mapped_count + 1 where name = '%s'" % kmlName)
                k.write("assignment: incremented mapped count by trusted worker for KML %s\n" % kmlName)
            else:
                assignmentStatus = MappingCommon.HITUntrusted

            # Record the final FQAQC or non-QAQC HIT status.
            self.cur.execute("""update assignment_data set status = '%s' where assignment_id = '%s'""" %
                (assignmentStatus, assignmentId))
            self.dbcon.commit()
            k.write("assignment: FQAQC or non-QAQC assignment marked in DB as %s\n" %
                assignmentStatus.lower())

            # Delete the HIT if all assignments have been submitted and have a final status
            # (i.e., there are no assignments in pending or assigned status).
            if self.deleteFinalizedHit(hitId, submitTime):
                k.write("assignment: hit has no remaining assignments and has been deleted\n")
            else:
                k.write("assignment: hit still has remaining assigned or pending assignments and cannot be deleted\n")

    # Revoke Mapping Africa qualification unconditionally unless not qualified.
    # Returns True if worker was qualified and qualification was revoked; False otherwise.
    def revokeQualification(self, workerId, submitTime, force=False):
        # Revoke the qualification if not already done.
        qualified = self.querySingleValue("SELECT qualified FROM worker_data WHERE worker_id = '%s'" % (workerId))
        if qualified or force:
            # Remove all user maps and training assignments for this worker.
            self.cur.execute("""DELETE FROM qual_user_maps WHERE assignment_id IN 
                    (SELECT assignment_id FROM qual_assignment_data WHERE worker_id = %s)""" %
                    workerId)
            self.cur.execute("DELETE FROM qual_assignment_data WHERE worker_id = %s" % workerId)
            # Mark worker as having lost his qualification.
            self.cur.execute("""UPDATE worker_data SET qualified = false, last_time = '%s' 
                    WHERE worker_id = %s""" % (submitTime, workerId))
            self.dbcon.commit()
            return True
        else:
            return False

    # Revoke Mapping Africa qualification if quality score 
    # shows worker as no longer qualified.
    def revokeQualificationIfUnqualifed(self, workerId, submitTime):
        qualityScore = self.getQualityScore(workerId)
        if qualityScore is None:
            return False
        revocationThreshold = float(self.getConfiguration('Qual_RevocationThreshold'))
        if qualityScore >= revocationThreshold:
            return False
        self.revokeQualification(workerId, submitTime)
        return True

    # Record worker as qualified and pay training bonus.
    def grantQualification(self, workerId, completionTime):
        # Mark worker as qualified.
        self.cur.execute("""UPDATE worker_data SET last_time = %s, qualified = true,
                scores = %s, returns = %s
                WHERE worker_id = %s""", (completionTime, [], [], workerId))

        # Check to see if training bonus should be paid.
        # NOTE: this will only be paid the first time the worker qualifies.
        bonusPaid = self.querySingleValue("""select bonus_paid from worker_data
                where worker_id = '%s'""" % workerId)
        if not bonusPaid:
            trainBonusAmount = self.getConfiguration('Bonus_AmountTraining')
            trainBonusReason = self.getConfiguration('Bonus_ReasonTraining')
            self.grantBonus(MappingCommon.EVTTrainingBonus, workerId, trainBonusAmount, trainBonusReason)
            self.cur.execute("UPDATE worker_data SET bonus_paid = true WHERE worker_id = %s" % \
                workerId)
        self.dbcon.commit()


    # Record assignment approval.
    def approveAssignment(self, workerId, assignmentId, submitTime, warning=False):
        if warning:
            hitWarningDescription = self.getConfiguration('HitQ_WarningDescription')
            hitNoWarningThreshold = float(self.getConfiguration('HitQ_NoWarningThreshold'))
            feedback = (hitWarningDescription % hitNoWarningThreshold)
        else:
            feedback = ''
        reward = self.querySingleValue("""select reward from hit_data
                inner join assignment_data using (hit_id)
                where assignment_id = '%s'""" % assignmentId)
        self.cur.execute("""INSERT INTO assignment_history (event_time, event_type, worker_id, assignment_id, amount, feedback)
               VALUES ('%s', '%s', %s, %s, %s, '%s')""" % \
               (submitTime, MappingCommon.EVTApprovedAssignment, workerId, assignmentId, reward, feedback))
        self.dbcon.commit()

    # Record assignment rejection.
    def rejectAssignment(self, workerId, assignmentId, submitTime):
        hitAcceptThreshold = float(self.getConfiguration('HitQ_AcceptThreshold'))
        feedback = (self.getConfiguration('Hit_RejectDescription') % hitAcceptThreshold)
        self.cur.execute("""INSERT INTO assignment_history (event_time, event_type, worker_id, assignment_id, amount, feedback)
               VALUES ('%s', '%s', %s, %s, %s, '%s')""" % \
               (submitTime, MappingCommon.EVTRejectedAssignment, workerId, assignmentId, '0', feedback))
        self.dbcon.commit()

    # Records bonuses for training completion and quality work.
    # Automatically inserts current time into row.
    def grantBonus(self, bonusType, workerId, bonus, reason):
        self.cur.execute("""INSERT INTO assignment_history (event_type, worker_id, amount, feedback)
               VALUES ('%s', %s, %s, '%s')""" % \
               (bonusType, workerId, bonus, reason))
        self.dbcon.commit()

    # Pay bonus and return True if quality score shows worker as qualified.
    def payBonusIfQualified(self, workerId):
        qualityScore = self.getQualityScore(workerId)
        if qualityScore is None:
            return 0
        bonusThreshold = self.getConfiguration('Bonus_Threshold4')
        if bonusThreshold != 'ignore' and qualityScore >= float(bonusThreshold):
            bonusAmount = self.getConfiguration('Bonus_Amount4')
            bonusReason = self.getConfiguration('Bonus_Reason4')
            self.grantBonus(MappingCommon.EVTQualityBonus, workerId, bonusAmount, bonusReason)
            return 4
        bonusThreshold = self.getConfiguration('Bonus_Threshold3')
        if bonusThreshold != 'ignore' and qualityScore >= float(bonusThreshold):
            bonusAmount = self.getConfiguration('Bonus_Amount3')
            bonusReason = self.getConfiguration('Bonus_Reason3')
            self.grantBonus(MappingCommon.EVTQualityBonus, workerId, bonusAmount, bonusReason)
            return 3
        bonusThreshold = self.getConfiguration('Bonus_Threshold2')
        if bonusThreshold != 'ignore' and qualityScore >= float(bonusThreshold):
            bonusAmount = self.getConfiguration('Bonus_Amount2')
            bonusReason = self.getConfiguration('Bonus_Reason2')
            self.grantBonus(MappingCommon.EVTQualityBonus, workerId, bonusAmount, bonusReason)
            return 2
        bonusThreshold = self.getConfiguration('Bonus_Threshold1')
        if bonusThreshold != 'ignore' and qualityScore >= float(bonusThreshold):
            bonusAmount = self.getConfiguration('Bonus_Amount1')
            bonusReason = self.getConfiguration('Bonus_Reason1')
            self.grantBonus(MappingCommon.EVTQualityBonus, workerId, bonusAmount, bonusReason)
            return 1
        return 0
