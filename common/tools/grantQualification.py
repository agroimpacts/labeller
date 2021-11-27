#! /usr/bin/python

import sys
sys.path.append("..")  # search one directory up
from datetime import datetime
from MappingCommon import MappingCommon

if  len(sys.argv) != 2:
    print "Usage: %s <login_email_address>" % sys.argv[0]
    sys.exit(1)

email = sys.argv[1]

mapc = MappingCommon()

workerId = mapc.querySingleValue("select id from users where email = '%s'" % email)
if workerId is None:
    print "Invalid email address."
    sys.exit(1)

now = str(datetime.today())

mapc.grantQualification(workerId, now)

print("Mapping Africa Qualification granted to worker %s (%s)." % (workerId, email))
