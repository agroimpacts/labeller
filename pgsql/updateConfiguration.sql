-- Relative URL to python scripts on Mapping Africa server
UPDATE configuration SET value = '/api' WHERE key = 'APIUrl';
-- Bonus amount in points.
UPDATE configuration SET value = '20' WHERE key = 'Bonus_Amount1';
-- Bonus amount in points.
UPDATE configuration SET value = '40' WHERE key = 'Bonus_Amount2';
-- Bonus amount in points.
UPDATE configuration SET value = '60' WHERE key = 'Bonus_Amount3';
-- Bonus amount in points.
UPDATE configuration SET value = '80' WHERE key = 'Bonus_Amount4';
-- Bonus amount in points.
UPDATE configuration SET value = '120' WHERE key = 'Bonus_AmountTraining';
-- Text provided as the reason for granting the level 1 bonus.
UPDATE configuration SET value = 'Congratulations! You have earned accuracy bonus level 1.' WHERE key = 'Bonus_Reason1';
-- Text provided as the reason for granting the level 2 bonus.
UPDATE configuration SET value = 'Congratulations! You have earned accuracy bonus level 2.' WHERE key = 'Bonus_Reason2';
-- Text provided as the reason for granting the level 3 bonus.
UPDATE configuration SET value = 'Congratulations! You have earned accuracy bonus level 3.' WHERE key = 'Bonus_Reason3';
-- Text provided as the reason for granting the level 4 bonus.
UPDATE configuration SET value = 'Congratulations! You have earned accuracy bonus level 4.' WHERE key = 'Bonus_Reason4';
-- Text provided as the reason for granting the training bonus.
UPDATE configuration SET value = 'Congratulations on your successful qualification for Mapping Africa! To thank you for your time, effort, and interest in qualifying, we are crediting this bonus to your account.' WHERE key = 'Bonus_ReasonTraining';
-- Moving average score worker must achieve to receive this bonus. May be set to 'ignore'.
UPDATE configuration SET value = '0.8' WHERE key = 'Bonus_Threshold1';
-- Moving average score worker must achieve to receive this bonus. May be set to 'ignore'.
UPDATE configuration SET value = '0.85' WHERE key = 'Bonus_Threshold2';
-- Moving average score worker must achieve to receive this bonus. May be set to 'ignore'.
UPDATE configuration SET value = '0.9' WHERE key = 'Bonus_Threshold3';
-- Moving average score worker must achieve to receive this bonus. May be set to 'ignore'.
UPDATE configuration SET value = '0.95' WHERE key = 'Bonus_Threshold4';
-- Used to determine risky pixels if risk is greater than this threshold (Pixel-level) 
UPDATE configuration SET value = '0.4' WHERE key = 'Consensus_RiskyPixelThreshold';
-- The threshold to give a warning for risky percentage for a consensus map (in 'generate_consensus_damon')
UPDATE configuration SET value = '0.1' WHERE key = 'Consensus_WarningThreshold';
-- In seconds: for generate_consensus_daemon script.
UPDATE configuration SET value = '120' WHERE key = 'FKMLCheckingInterval';
-- Total number of HITs of each type (F, N, Q) to be maintained. Should be set to twice the maximum number of concurrent workers in production.
UPDATE configuration SET value = '20' WHERE key = 'Hit_AvailTarget';
-- (24 hours) Max assignment duration in seconds of standard Mapping Africa HIT. An assigned HIT is considered abandoned if not submitted before this time elapses.
UPDATE configuration SET value = '86400' WHERE key = 'Hit_Duration';
-- Percentage of HITs assigned to a worker that are to be F HITs. Only used in Hit_StandAlone mode.
UPDATE configuration SET value = '80' WHERE key = 'Hit_FqaqcPercentage';
-- Score a training HIT must achieve to be accepted.
UPDATE configuration SET value = '0.4' WHERE key = 'HitI_AcceptThreshold';
-- Max assignments of Future QAQC Mapping Africa HITs
UPDATE configuration SET value = '5' WHERE key = 'Hit_MaxAssignmentsF';
-- Max assignments of standard non-QAQC Mapping Africa HITs 
UPDATE configuration SET value = '2' WHERE key = 'Hit_MaxAssignmentsN';
-- Quality score a worker must achieve to have his non-QAQC HITs be marked as 'trusted'
UPDATE configuration SET value = '0.45' WHERE key = 'HitN_TrustThreshold';
-- (24 hours) Max time in seconds that an assignment can remain in the Pending state before assuming that the worker has quit.
UPDATE configuration SET value = '86400' WHERE key = 'Hit_PendingAssignLimit';
-- In seconds: for HIT-creation and other daemons.
UPDATE configuration SET value = '10' WHERE key = 'Hit_PollingInterval';
-- Score a QAQC HIT must achieve to be accepted and worker paid, possibly with a warning.
UPDATE configuration SET value = '0.4' WHERE key = 'HitQ_AcceptThreshold';
-- Percentage of HITs assigned to a worker that are to be Q HITs: default will be 20 in production.
UPDATE configuration SET value = '20' WHERE key = 'Hit_QaqcPercentage';
-- Score a QAQC HIT meeting the accept threshold must achieve for worker to be paid without a warning.
UPDATE configuration SET value = '0.42' WHERE key = 'HitQ_NoWarningThreshold';
-- This is the warning workers get when their score is >= the accept threshold but < no-warning threshold.
UPDATE configuration SET value = 'Just FYI, this map is below the minimum desired accuracy, which is %s. If you submit too many maps below this level of accuracy, you will reduce your average score below the level required to maintain your qualification.' WHERE key = 'HitQ_WarningDescription';
-- Message sent to user in the event of a HIT assignment score below threshold
UPDATE configuration SET value = 'We are sorry, but your accuracy score was too low (<%s) to accept your results.' WHERE key = 'Hit_RejectDescription';
-- Fraction of an FQAQC HIT's max_assignments that must have been assigned for HIT to be considered soon-to-be-unassignable and hence eligible to be replaced. Range=0.0-1.0. 0.0 = only one assignment must have been assigned to mark HIT as replaceable. 1.0 = all assignments must have been assigned to mark HIT as replaceable.
UPDATE configuration SET value = '0' WHERE key = 'Hit_ReplacementThreshold_F';
-- Fraction of a non-QAQC HIT's max_assignments that must have been assigned for HIT to be considered soon-to-be-unassignable and hence eligible to be replaced. Range=0.0-1.0. 0.0 = only one assignment must have been assigned to mark HIT as replaceable. 1.0 = all assignments must have been assigned to mark HIT as replaceable.
UPDATE configuration SET value = '0.5' WHERE key = 'Hit_ReplacementThreshold_N';
-- Reward in points for successfully mapping a standard HIT
UPDATE configuration SET value = '5' WHERE key = 'Hit_Reward';
-- Reward increment amount based on hit difficulty (fwts). This is the first of two terms in a linear or polynomial reward increment function.
UPDATE configuration SET value = '0.17' WHERE key = 'Hit_RewardIncrement';
-- Reward increment. This is the second of two terms in a linear or polynomial reward increment function. If linear, value should be set to 0. 
UPDATE configuration SET value = '-0.016' WHERE key = 'Hit_RewardIncrement2';
-- If true, mapper code operates independently, and handle F KMLs in the original way. If false, mapper code operates in conjunction with cvml code.
UPDATE configuration SET value = 'false' WHERE key = 'Hit_StandAlone';
-- The defined number of initial F sites inserted into incoming_names as iteration 0.
UPDATE configuration SET value = '100' WHERE key = 'InitialFnum';
-- 
UPDATE configuration SET value = '' WHERE key = 'IssueAlertAssignee';
-- 
UPDATE configuration SET value = 'Internal Alert' WHERE key = 'IssueAlertLabel';
-- 
UPDATE configuration SET value = '' WHERE key = 'IssueGeneralInquiryAssignee';
-- 
UPDATE configuration SET value = 'General Inquiry' WHERE key = 'IssueGeneralInquiryLabel';
-- 
UPDATE configuration SET value = '' WHERE key = 'IssueWorkerInquiryAssignee';
-- 
UPDATE configuration SET value = 'Worker Feedback' WHERE key = 'IssueWorkerInquiryLabel';
-- Default latitude differential value to convert a point to a KML grid cell
UPDATE configuration SET value = '0.0025' WHERE key = 'KMLdlat';
-- Default longitude differential value to convert a point to a KML grid cell
UPDATE configuration SET value = '0.0025' WHERE key = 'KMLdlon';
-- Height in pixels of the entire iframe for map display
UPDATE configuration SET value = '730' WHERE key = 'KMLFrameHeight';
-- Script to display KML map and bounding box
UPDATE configuration SET value = 'getkml' WHERE key = 'KMLFrameScript';
-- Relative URL to KML files on Mapping Africa server (was: kmls/${kmlName}.kml)

UPDATE configuration SET value = 'genkml?kmlName=${kmlName}' WHERE key = 'KMLGenScript';
-- 
UPDATE configuration SET value = 'Please use the toolbar below to map all crop fields that are wholly or partially inside the white square (map the entire field, even the part that falls outside the box). <br/> Then save your changes by clicking on the disk icon to complete the HIT. Please visit our <a href="http://mappingafrica.princeton.edu/blog.html#!/blog/posts/Frequently-Asked-Questions/6" target="_blank">FAQ</a> for tips on dealing with no imagery and for other advice.' WHERE key = 'KMLInstructions';
-- Height in pixels of the map display portion of the iframe
UPDATE configuration SET value = '635' WHERE key = 'KMLMapHeight';
-- In seconds: for Normal KML generation script.
UPDATE configuration SET value = '600' WHERE key = 'KMLPollingInterval';
-- Relative URL to reference and worker maps in KML file format on Mapping Africa server
UPDATE configuration SET value = '/maps' WHERE key = 'MapUrl';
-- On mapper server: target for minimum number of available normal KMLs.
UPDATE configuration SET value = '50' WHERE key = 'MinAvailNKMLTarget';
-- generate_consensus_daemon: minimum number of mapped kml for creating consensus map.
UPDATE configuration SET value = '5' WHERE key = 'MinimumMappedCount';
-- Number of Normal KMLs produced whenever number of available KMLs on the mapper server drops below MinAvailNKMLTarget.
UPDATE configuration SET value = '500' WHERE key = 'NKMLBatchSize';
-- The defined proportion of holdout in initial F sites in incoming_names
UPDATE configuration SET value = '0.7' WHERE key = 'ProportionHoldout';
-- The defined proportion of holdout1 in holdout in incoming_names
UPDATE configuration SET value = '0.07' WHERE key = 'ProportionHoldout1';
-- Number of notifications to use for computing % return of HITs for quality score. Should be 10 in production.
UPDATE configuration SET value = '10' WHERE key = 'Quality_ReturnHistDepth';
-- Value from 0.0 to 1.0 to indicate the weight that a return should have in the quality score. Should be 1.0 in production.
UPDATE configuration SET value = '1.0' WHERE key = 'Quality_ReturnWeight';
-- Number of scores to use for computing moving average of scores for quality score. Should be 10 in production.
UPDATE configuration SET value = '5' WHERE key = 'Quality_ScoreHistDepth';
-- Message sent to user in the event of a Mapping Africa qualification revocation
UPDATE configuration SET value = 'We are sorry, but your accuracy scores have been consistently too low, so we must revoke your Mapping Africa qualification. Please feel free to review the training video and retake the qualification test.' WHERE key = 'Qual_RevocationDescription';
-- Moving average score below which a worker has their Mapping Africa qualification revoked.
UPDATE configuration SET value = '0.6' WHERE key = 'Qual_RevocationThreshold';
-- Instructional video file name
UPDATE configuration SET value = 'mappingafrica_tutorial.swf' WHERE key = 'QualTest_InstructionalVideo';
-- Instructional video height in pixels
UPDATE configuration SET value = '480' WHERE key = 'QualTest_InstructionalVideoHeight';
-- Instructional video width in pixels
UPDATE configuration SET value = '640' WHERE key = 'QualTest_InstructionalVideoWidth';
-- Introductory video file name
UPDATE configuration SET value = 'mapping_africa_intro.swf' WHERE key = 'QualTest_IntroVideo';
-- Intro video height in pixels
UPDATE configuration SET value = '480' WHERE key = 'QualTest_IntroVideoHeight';
-- Intro video width in pixels
UPDATE configuration SET value = '640' WHERE key = 'QualTest_IntroVideoWidth';
-- Text presented to returning worker upon completion of the Training Frame page.
UPDATE configuration SET value = 'Congratulations! You have successfully completed all %(totCount)d training maps. You are now qualified to select "Map Agricultural Fields" in the Employee submenu.' WHERE key = 'QualTest_TF_TextEnd';
-- Text presented to returning worker on the Training Frame page.
UPDATE configuration SET value = 'You have successfully completed %(doneCount)d of %(totCount)d maps.' WHERE key = 'QualTest_TF_TextMiddle';
-- Text presented to new worker on the Training Frame page.
UPDATE configuration SET value = 'You will now briefly work on %(totCount)d maps to get hands-on familiarity with identifying and labeling agricultural fields.' WHERE key = 'QualTest_TF_TextStart';
-- S3 bucket directory for storing testing, holdout, and train label maps
UPDATE configuration SET value = 'activemapper' WHERE key = 'S3BucketDir';
-- Max time in minutes that a worker session will remain logged in while inactive. Should be set to 10 hours (600) in production.
UPDATE configuration SET value = '600' WHERE key = 'SessionLifetime';
-- Snap tolerance in pixels
UPDATE configuration SET value = '4' WHERE key = 'SnapTolerance';
-- The threshold of accuracy gain to stop the active learning loop
UPDATE configuration SET value = '0.01' WHERE key = 'StoppingFunc_AccGainThres';
-- The accuracy threshold to stop the iteration
UPDATE configuration SET value = '0.85' WHERE key = 'StoppingFunc_AccThres';
-- The maximum iteration number for stopping active learning loop
UPDATE configuration SET value = '30' WHERE key = 'StoppingFunc_MaxIterations';
-- Relative URL to videos on Mapping Africa server
UPDATE configuration SET value = '/videos' WHERE key = 'VideoUrl';
