import sys
import os
import re
import click
import yaml
import boto3

home = os.environ['HOME']
projectRoot = '%s/labeller' % home
sys.path.append("%s/common" % projectRoot)
from MappingCommon import MappingCommon


def update_config(instance, items):
    keys = ["labeller", "learner", "terraform"]

    # For now, only need to change worker_count.
    # If there is any more, will add in the future
    items_terraform = ["worker_count"]
    if instance not in keys:
        sys.exit("Invalid instance name, should be labeller, learner or terraform.")

    if instance == "terraform":
        variables_path = "%s/terraform/%s" % (projectRoot, "variables.tf")
        emr_path = "%s/terraform/%s" % (projectRoot, "emr.tf")

        def change_variables(old_content, params, new_default):
            lines = re.findall('variable "%s" {(?s).*?}' % params, old_content)
            line = re.findall('default(?s).*?= ".*?"', lines[0])
            old = re.findall('".*?"', line[0])
            line_new = line[0].replace(old[0], '"%s"' % new_default)
            lines_new = lines[0].replace(line[0], line_new)
            new_content = old_content.replace(lines[0], lines_new)
            return new_content

        def change_emr(old_content, params, new_value, pos_index):
            lines = re.findall('step {\n *name="%s"(?s).*?}' % params, old_content)
            line = re.findall('args = \[.*?\]', lines[0])
            old = line[0].split('", "')[pos_index]
            if pos_index == 15:
                line_new = line[0].replace('--probability-images", "%s"' % old,
                                           '--probability-images", "%s"' % str(new_value))
            elif pos_index == 19:
                line_new = line[0].replace('activemapper", "%s"' % old, 'activemapper", "%s"' % str(new_value))
            else:
                line_new = line[0].replace("%s" % old, "%s" % str(new_value))
            lines_new = lines[0].replace(line[0], line_new)
            new_content = old_content.replace(lines[0], lines_new)
            return new_content

        with open(variables_path, "r") as f:
            variables = f.read()

        with open(emr_path, "r") as f:
            emr = f.read()

        for i in range(len(items)):
            value = raw_input("The value for %s is: " % items[i])
            if value.isdigit():
                value = int(value)
                num_shuffle = value * 4 * 2
                variables = change_variables(old_content=variables,
                                             params="worker_count",
                                             new_default=value)
                emr = change_emr(old_content=emr, params="run_geopyspark.py",
                                 new_value=num_shuffle, pos_index=10)

                with open(variables_path, "w") as f:
                    f.write(variables)

                with open(emr_path, "w") as f:
                    f.write(emr)
            else:
                sys.exit("Invalid input, should be integer.")
    else:
        mapc = MappingCommon()
        yaml_file = "%s/common/config.yaml" % projectRoot
        items = list(items)
        if os.path.isfile(yaml_file):
            config = mapc.parseYaml("config.yaml")
        else:
            sys.exit("No config yaml generated yet, please generate file first.")

        if (instance == "labeller") and (not all(elem in config["labeller"].keys() for elem in items)):
            sys.exit("Invalid items for labeller.")
        elif (instance == "learner") and (not all(elem in config["learner"].keys() for elem in items)):
            sys.exit("Invalid items for learner.")
        elif (instance == "terraform") and (not all(elem in items_terraform for elem in items)):
            sys.exit("Invalid items for terraform.")

        for i in range(len(items)):
            if (items[i] == "runid") or (items[i] == "aoiid"):
                sys.exit("Changing runid or aoiid is dangerous, "
                         "there are a few other files should be changed simultaneously. "
                         "it should be set by fire_up_mapper. ")
            value = raw_input("The value for %s is: " % items[i])
            if value.isdigit():
                value = int(value)
            else:
                try:
                    value = float(value)
                except ValueError:
                    value = str(value)
            config[instance][items[i]] = value

        # Remove the null from the output file
        def represent_none(self, _):
            return self.represent_scalar(u'tag:yaml.org,2002:null', u'')

        yaml.SafeDumper.add_representer(type(None), represent_none)
        with open(yaml_file, "w") as f:
            yaml.safe_dump(config, f, default_flow_style=False)

        aws_session = boto3.session.Session(aws_access_key_id=config['learner']['aws_access'],
                                            aws_secret_access_key=config['learner']['aws_secret'],
                                            region_name=config['learner']['aws_region'])
        s3_client = aws_session.client('s3', region_name=config['learner']['aws_region'])

        des_on_s3 = "config_" + config['learner']['aoiid'] + ".yaml"
        s3_client.upload_file(yaml_file, config['learner']['bucket'], des_on_s3)


@click.command()
@click.argument(u'instance', nargs=1, required=True)
@click.argument(u'items', nargs=-1, required=True)
def main(instance, items):
    update_config(instance, items)


if __name__ == "__main__":
    main()
