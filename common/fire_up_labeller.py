# Author: Lei Song
# The code to set up the labeller for working,
# To understand it, you should be familiar with
# at least config.yaml, emr.tf, and variables.tf

import yaml
import re
import boto3
import sys
import os
import click
from math import floor


# check worker_mem_yarn at:
# https://docs.aws.amazon.com/emr/latest/ReleaseGuide/emr-hadoop-task-config.html#emr-hadoop-task-config
def fire_up_labeller(initial=3,
                     ec2_instance="start",
                     run_id=0,
                     aoi_index=1,
                     aoi_name="aoi",
                     aoi_s3_object=None,
                     incoming_names_static_path=None,
                     github_branch="devel",
                     github_repo="agroimpacts/issues",
                     security_group_id="sg-ac924ee6",
                     worker_type="m4.2xlarge",
                     bid_price=0.16,
                     worker_count=50,
                     secret_key=None,
                     db_user=None,
                     db_pwd=None,
                     github_token=None,
                     api_key=None,
                     aws_access=None,
                     aws_secret=None,
                     aws_region=None,
                     bucket="activemapper",
                     number_outgoing_names=10,
                     num_possibilities=20,
                     slack_url=None,
                     worker_vcpu=16,
                     worker_mem_yarn=24,
                     executor_cores=5,
                     image_catalog_predict=None):
    # Set the config.yaml
    # Parse the config template
    home = os.environ['HOME']

    projectRoot = '%s/labeller' % home
    config_template = "%s/common/%s" % (projectRoot, "config_template.yaml")
    with open(config_template, 'r') as yaml_file:
        config = yaml.safe_load(yaml_file)
    config_path = "%s/common/%s" % (projectRoot, "config.yaml")

    # Get the incoming_names_file
    if incoming_names_static_path is None:
        print("You leave this blank, so just set it to incoming_names_static_cluster_blank.csv.")
        incoming_names_file_path = "incoming_names_static_cluster_blank.csv"
    else:
        incoming_names_file_path = incoming_names_static_path

    # Check the initial mode index
    if initial not in [1, 2, 3]:
        sys.exit("Invalid initial mode index! Should be in [1, 2, 3].")

    # Set parameters
    f_pool_file = "f_pool_%s_%d.csv" % (aoi_name, aoi_index)
    qs_pool_file = "q_sites_%s_%d.csv" % (aoi_name, aoi_index)
    incoming_names_file = "incoming_names_%s_%d.csv" % (aoi_name, aoi_index)
    incoming_metrics_file = "incoming_metrics_%s_%d.csv" % (aoi_name, aoi_index)
    image_catalog_file = "planet/planet_catalog_%s_%d.csv" % (aoi_name, aoi_index)
    if image_catalog_predict is None:
        image_catalog_predict = image_catalog_file
    image_output_pattern = "s3://activemapper/classified-images/%s_%d/image_c{}_r{}_{}_run{}_iteration{}.tif" \
                           % (aoi_name, aoi_index)
    outgoing_names_file = "s3://activemapper/planet/outgoing_names_%s_%d.csv" \
                          % (aoi_name, aoi_index)
    # spark
    worker_executor = floor((worker_vcpu - 1) / executor_cores)
    executor_mem = floor((worker_mem_yarn / worker_executor) - 1)
    executor = worker_executor * worker_count - 1
    num_shuffle = executor * executor_cores * 2

    # Set the values
    # labeller
    config['labeller']['DEBUG'] = True
    config['labeller']['initial'] = initial
    config['labeller']['SECRET_KEY'] = secret_key
    config['labeller']['slack_url'] = slack_url
    config['labeller']['db_production_name'] = 'Africa'
    config['labeller']['db_username'] = db_user
    config['labeller']['db_password'] = db_pwd
    config['labeller']['github_token'] = github_token
    config['labeller']['github_repo'] = github_repo
    config['labeller']['MAIL_SERVER'] = "localhost"
    config['labeller']['MAIL_PORT'] = 25
    config['labeller']['PL_API_KEY'] = api_key
    config['labeller']['aws_access'] = aws_access
    config['labeller']['aws_secret'] = aws_secret
    config['labeller']['aws_region'] = aws_region
    config['labeller']['mapping_category1'] = "field"
    config['labeller']['consensus_directory'] = "/labels/%s/" % aoi_name
    config['labeller']['consensus_heatmap_dir'] = "heatmaps/%s" % aoi_name
    config['labeller']['s3_catalog_name'] = "planet_catalog_%s_full.csv" % aoi_name
    config['labeller']['aoi_s3_object'] = "grid/%s" % aoi_s3_object

    # learner
    config['learner']['aws_access'] = aws_access
    config['learner']['aws_secret'] = aws_secret
    config['learner']['aws_region'] = aws_region
    config['learner']['runid'] = int(run_id)
    config['learner']['aoiid'] = aoi_index
    config['learner']['aoiname'] = aoi_name
    config['learner']['bucket'] = "activemapper"
    config['learner']['prefix'] = "planet"
    config['learner']['pool'] = f_pool_file
    config['learner']['qs'] = qs_pool_file
    config['learner']['incoming_names'] = incoming_names_file
    config['learner']['incoming_names_static'] = incoming_names_file_path
    config['learner']['metrics'] = incoming_metrics_file
    config['learner']['image_catalog'] = image_catalog_file
    config['learner']['image_catalog_predict'] = image_catalog_predict
    config['learner']['image_output_pattern'] = image_output_pattern
    config['learner']['outgoing'] = outgoing_names_file
    config['learner']['number_outgoing_names'] = int(number_outgoing_names)

    # Set the private ip of the instance
    aws_session = boto3.session.Session(aws_access_key_id=config['learner']['aws_access'],
                                        aws_secret_access_key=config['learner']['aws_secret'],
                                        region_name=config['learner']['aws_region'])
    ec2_instances = aws_session.resource('ec2').instances.filter(
        Filters=[{
            'Name': 'tag:Name',
            'Values': [ec2_instance]}])
    try:
        private_ip = [instance.private_ip_address for instance in ec2_instances][0]
        subnet = [instance.subnet_id for instance in ec2_instances][0]
    except IndexError:
        sys.exit("No such instance, please check this on AWS console.")

    config['labeller']['db_host'] = private_ip

    # Remove the null from the output file
    def represent_none(self, _):
        return self.represent_scalar(u'tag:yaml.org,2002:null', u'')

    yaml.SafeDumper.add_representer(type(None), represent_none)
    with open(config_path, "w") as f:
        yaml.safe_dump(config, f, default_flow_style=False)

    s3_client = aws_session.client('s3', region_name=config['learner']['aws_region'])

    des_on_s3 = "config_%s_%d.yaml" % (aoi_name, aoi_index)
    s3_client.upload_file(config_path, bucket, des_on_s3)

    # Set the emr.tf and variables.tf
    emr_path = "%s/terraform/%s" % (projectRoot, "emr_template.tf")
    variables_path = "%s/terraform/%s" % (projectRoot, "variables_template.tf")
    emr_path_new = "%s/terraform/%s" % (projectRoot, "emr.tf")
    variables_path_new = "%s/terraform/%s" % (projectRoot, "variables.tf")

    def change_variables(old_content, params, new_default):
        lines = re.findall('variable "%s" {(?s).*?}' % params, old_content)
        line = re.findall('default(?s).*?= ".*?"', lines[0])
        old = re.findall('".*?"', line[0])
        line_new = line[0].replace(old[0], '"%s"' % new_default)
        lines_new = lines[0].replace(line[0], line_new)
        new_content = old_content.replace(lines[0], lines_new)
        return new_content

    with open(variables_path, "r") as f:
        variables = f.read()
    variables = change_variables(old_content=variables, params="worker_count", new_default=worker_count)
    variables = change_variables(old_content=variables, params="worker_type", new_default=worker_type)
    variables = change_variables(old_content=variables, params="bid_price", new_default=bid_price)
    variables = change_variables(old_content=variables, params="security_group", new_default=security_group_id)
    variables = change_variables(old_content=variables, params="subnet", new_default=subnet)

    with open(variables_path_new, "w+") as f:
        f.write(variables)

    def change_emr(old_content, params, step):

        # run_geopyspark
        param = params[step]
        lines = re.findall('step {\n *name="%s"(?s).*?}' % step, old_content)[0]
        line = re.findall('args = \[.*?\]', lines)[0] \
            .replace('"]', '') \
            .split('", "')
        content = old_content
        lines_new = lines
        for key in param.keys():
            if "spark" in key:
                old = [m for m in line if m.startswith(key)][0]
                pos_index = line.index(old)
                new = "%s=%s" % (key, str(param[key]))
            elif "-" in key:
                new = param[key]
                pos_index = line.index(key) + 1
            else:
                try:
                    pos_index, new = param[key]
                except:
                    sys.exit("Please provide both pos_index and new value for %s!" % param[key])

            lines_new = lines_new.replace('"%s"' % line[pos_index], '"%s"' % str(new))
        content = content.replace(lines, lines_new)

        return content

    emr_params = {
        "Clone Learner": {
            "-b": github_branch
        },
        "run_geopyspark.py": {
            "spark.executor.instances": executor,
            "spark.executor.cores": executor_cores,
            "spark.executor.memory": "%dg" % executor_mem,
            "spark.driver.cores": executor_cores,
            "spark.driver.memory": "%dg" % executor_mem,
            "spark.sql.shuffle.partition": num_shuffle,
            "spark.default.parallelism": num_shuffle,
            "--config-filename": des_on_s3,
            "--probability-images": num_possibilities,
            "run": (-2, run_id),
            "aoi": (-1, aoi_index),
        },
        "run_DB_insert.py": {
            "--config-filename": des_on_s3
        }
    }

    with open(emr_path, "r") as f:
        emr = f.read()
    emr = change_emr(old_content=emr, params=emr_params, step="Clone Learner")
    emr = change_emr(old_content=emr, params=emr_params, step="run_geopyspark.py")
    emr = change_emr(old_content=emr, params=emr_params, step="run_DB_insert.py")

    with open(emr_path_new, "w+") as f:
        f.write(emr)


@click.command()
@click.option('--initial', default=2, type=int, help='The labeller mode: 1 initial; 2 single; 3 regular.')
@click.option('--ec2_instance', default='start', help='The name of the labeller instance.')
@click.option('--run_id', default=0, type=int, help='The run id of the iteration.')
@click.option('--aoi_index', default=1, help='The index of the aoi in geojson the iteration will run on.')
@click.option('--aoi_name', default="aoi", help='The general name of the aoi.')
@click.option('--aoi_s3_object', default="image_target_aois.geojson", help='The name of AOI geojson in '
                                                                           'S3/activemapper/grid.')
@click.option('--incoming_names_static_path', default='incoming_names_static_cluster_blank.csv', help='The S3 path of static '
                                                                                              'incoming names.')
@click.option('--github_branch', default="master", help='The branch name of learner to pull.')
@click.option('--github_repo', default="agroimpacts/issues", help='The repo to steer issues to.')
@click.option('--worker_type', default="m4.xlarge", help='The worker type of emr worker.')
@click.option('--bid_price', default=0.086, type=float, help='The bid price of emr worker.')
@click.option('--worker_count', default=200, type=int, help='The number of emr worker.')
@click.option('--bucket', default="activemapper", help='The name for S3 bucket.')
@click.option('--number_outgoing_names', default=10, type=int, help='The number of outgoing names.')
@click.option('--num_possibilities', default=20, type=int, help='The number of possibility maps to save out each '
                                                                'iteration.')
@click.option('--security_group_id', default=None, help='The security group id of learner.')
@click.option('--secret_key', default=None, help='The secret key for labeller.')
@click.option('--db_user', default=None, help='The name of database user.')
@click.option('--db_pwd', default=None, help='The password of database.')
@click.option('--github_token', default=None, help='The github token of maphelp.')
@click.option('--api_key', default=None, help='The api key for downloading planet.')
@click.option('--aws_access', default=None, help='The aws access key.')
@click.option('--aws_secret', default=None, help='The aws secret key.')
@click.option('--aws_region', default=None, help='The aws region.')
@click.option('--slack_url', default=None, help='The url of slack APP.')
@click.option('--worker_vcpu', default=16, type=int, help='The number of cup for workers.')
@click.option('--worker_mem_yarn', default=24, type=int, help='The size of memeory yarn for workers.')
@click.option('--executor_cores', default=5, type=int, help='The number of executor cores for workers.')
@click.option('--image_catalog_predict', default=None, help='The catalog of images to apply the model.')
def main(initial, ec2_instance, run_id, aoi_index, aoi_name, aoi_s3_object, incoming_names_static_path,
         github_branch, github_repo, worker_type, bid_price, worker_count, bucket,
         number_outgoing_names, num_possibilities, security_group_id,
         secret_key, db_user, db_pwd, github_token, api_key,
         aws_access, aws_secret, aws_region, slack_url,
         worker_vcpu, worker_mem_yarn, executor_cores,
         image_catalog_predict):
    fire_up_labeller(initial, ec2_instance, run_id, aoi_index, aoi_name, aoi_s3_object, incoming_names_static_path,
                     github_branch, github_repo, security_group_id, worker_type, bid_price, worker_count,
                     secret_key, db_user, db_pwd, github_token, api_key, aws_access,
                     aws_secret, aws_region, bucket, number_outgoing_names, num_possibilities,
                     slack_url, worker_vcpu, worker_mem_yarn, executor_cores, image_catalog_predict)


if __name__ == "__main__":
    main()
