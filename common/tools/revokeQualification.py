#! /usr/bin/python

import sys
sys.path.append("..")  # search one directory up
from datetime import datetime
from MappingCommon import MappingCommon

if  not (len(sys.argv) == 2 or (len(sys.argv) == 3 and sys.argv[1] == '-f')):
    print "Usage: %s [-f] <login_email_address>" % sys.argv[0]
    sys.exit(1)

if len(sys.argv) == 2:
    force = False
    email = sys.argv[1]
else:
    force = True
    email = sys.argv[2]

mapc = MappingCommon()

workerId = mapc.querySingleValue("select id from users where email = '%s'" % email)
if workerId is None:
    print "Invalid email address."
    sys.exit(1)

now = str(datetime.today())

revoked = mapc.revokeQualification(workerId, now, force=force)

if revoked:
    print("Mapping Africa Qualification revoked from worker %s (%s)." % (workerId, email))
else:
    print("Worker %s (%s) is not currently qualified." % (workerId, email))
