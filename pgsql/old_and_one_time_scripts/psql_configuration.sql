INSERT INTO configuration (key,value,comment) VALUES ('FqaqcHitPercentage', '25', 'Percentage of hits on MTurk server that are Future QAQC sites');
INSERT INTO configuration (key,value,comment) VALUES ('Hit_MaxAssignmentsF', '3', 'Max assignments of Future QAQC Mapping Africa HITs');
INSERT INTO configuration (key,value,comment) VALUES ('HitType_RewardIncrement', '0.15', 'Reward increment amount based on hit type');
update configuration set value=8 where key = 'AvailHitTarget';
update configuration set value=25 where key = 'QaqcHitPercentage';

ALTER TABLE kml_data ADD COLUMN fwts INTEGER;
UPDATE kml_data SET fwts=1;
ALTER TABLE kml_data ALTER COLUMN fwts SET NOT NULL;
ALTER TABLE kml_data ALTER COLUMN fwts SET DEFAULT 1;
