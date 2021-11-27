## Author: Lei Song
## To wake up the learner by using terraform
## it is used in generate_consensus_daemon.py
## but also can be used independently

# Must be run from same dir as terraform variables
# terraform binary must be callable from shell
import os
import re
from MappingCommon import MappingCommon
import subprocess


def main():
    # sets up .terraform/
    mapc = MappingCommon()
    os.chdir(mapc.projectRoot + "/terraform")
    rf_init = subprocess.Popen(mapc.projectRoot + "/terraform/terraform init", shell=True,
                               cwd=mapc.projectRoot + "/terraform").wait()
    # starts cvml cluster and a single iteration
    os.chdir(mapc.projectRoot + "/terraform")
    id_cluster = subprocess.Popen(mapc.projectRoot + "/terraform/terraform apply -auto-approve",
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=True).communicate()[0]
    if rf_init == 0 and (not not id_cluster):
        try:
            if bool(re.match("^[a-z]-[a-zA-Z0-9]+$", str.split(str.split(id_cluster, "\n")[-3], " = ")[1])):
                return str.split(str.split(id_cluster, "\n")[-3], " = ")[1]
            else:
                return False
        except IndexError, error:
            print error
            return False
    else:
        return False


if __name__ == "__main__":
    main()
