## Author: Lei Song
## To save out the full catalog when the accuracy is good enough
## Ideally, this script should be called by generate_consensus_daemon.py
## when IsFinished is True, but the system itself is not ready yet.

import os
import re
import yaml
import boto3

home = os.environ['HOME']

projectRoot = '%s/labeller' % home
config_path = "%s/common/%s" % (projectRoot, "config.yaml")
with open(config_path, 'r') as yaml_file:
    config = yaml.safe_load(yaml_file)

config['learner']['image_output_pattern'] = "s3://activemapper/classified-images/%s_whole/" \
                                         "image_c{}_r{}.tif" % config['learner']['aoiid']
config['learner']['image_catalog_fix'] = 'planet/planet_catalog_{}_fix.csv'.format(config['learner']['aoiid'])


# Remove the null from the output file
def represent_none(self, _):
    return self.represent_scalar(u'tag:yaml.org,2002:null', u'')


yaml.SafeDumper.add_representer(type(None), represent_none)
with open(config_path, "w") as f:
    yaml.safe_dump(config, f, default_flow_style=False)

aws_session = boto3.session.Session(aws_access_key_id=config['learner']['aws_access'],
                                    aws_secret_access_key=config['learner']['aws_secret'],
                                    region_name=config['learner']['aws_region'])
s3_client = aws_session.client('s3', region_name=config['learner']['aws_region'])

des_on_s3 = "config_%s_whole.yaml" % config['learner']['aoiid']

s3_client.upload_file(config_path, "activemapper", des_on_s3)

emr_path = "%s/terraform/%s" % (projectRoot, "emr.tf")


def change_emr(old_content, params, new_value, pos_index):
    lines = re.findall('step {\n *name="%s"(?s).*?}' % params, old_content)
    line = re.findall('args = \[.*?\]', lines[0])
    old = line[0].split('", "')[pos_index]
    if pos_index == -6:
        line_new = line[0].replace('--probability-images", "%s"' % old,
                                   '--probability-images", "%s"' % str(new_value))
    elif pos_index == -2:
        line_new = line[0].replace('activemapper", "%s"' % old, 'activemapper", "%s"' % str(new_value))
    elif pos_index == -3:
        line_new = line[0].replace('activemapper', '%s", "activemapper' % str(new_value))
    else:
        line_new = line[0].replace("%s" % old, "%s" % str(new_value))
    lines_new = lines[0].replace(line[0], line_new)
    new_content = old_content.replace(lines[0], lines_new)
    return new_content


with open(emr_path, "r") as f:
    emr = f.read()
emr = change_emr(old_content=emr, params="run_geopyspark.py", new_value=str(config['learner']['aoiid']) + '"]',
                 pos_index=-1) # aoi_id
emr = change_emr(old_content=emr, params="run_geopyspark.py", new_value="--output-all-images", pos_index=-3)
emr = change_emr(old_content=emr, params="run_geopyspark.py",
                 new_value=des_on_s3, pos_index=-9)




try:
    lines = re.findall('step {\n *name="%s"(?s).*?}' % "run_DB_insert.py", emr)[0]
    emr = emr.replace(lines+"}", "")
except IndexError:
    exit("Run_DB_insert already gone!")
with open(emr_path, "w") as f:
    f.write(emr)
