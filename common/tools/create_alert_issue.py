#! /usr/bin/python

# This script is called by scripts running under crontab, and that environment 
# does not have PYHTHONPATH defined, so we need to add it to sys.path here.

import sys
import os
home = os.environ['HOME']
projectRoot = '%s/labeller' % home
sys.path.append("%s/common" % projectRoot)

from MappingCommon import MappingCommon

if  not ((len(sys.argv) == 3 and sys.argv[1] != '-n') or (len(sys.argv) == 4 and sys.argv[1] == '-n')):
    print "Usage: %s [-n] <issue_title> <issue_description>" % sys.argv[0]
    sys.exit(1)

if len(sys.argv) == 3:
    prefix = True
    title = sys.argv[1]
    desc = sys.argv[2]
else:
    prefix = False
    title = sys.argv[2]
    desc = sys.argv[3]

mapc = MappingCommon()
mapc.createAlertIssue(title, desc, prefix)
