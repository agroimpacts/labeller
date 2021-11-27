#! /usr/bin/python

import sys
from MappingCommon import MappingCommon

mapc = MappingCommon()

if len(sys.argv) > 1:
    hits = mapc.getAssignableHitInfo(int(sys.argv[1].rstrip()))
else:
    hits = mapc.getHitInfo()

nh = 0
nah = 0
nqh = 0
nfh = 0
nnh = 0
print "HIT Id\tkml name\ttype\treward\tstatus\t\t#rem\t#asgnd\t#pend\t#comp"
for hitId, hit in sorted(hits.iteritems()):
    nh = nh + 1
    kmlType = hit['kmlType']
    if hit['status'] == 'Assignable':
        nah = nah + 1
        if kmlType == MappingCommon.KmlQAQC:
            nqh = nqh + 1
        elif kmlType == MappingCommon.KmlFQAQC:
            nfh = nfh + 1
        elif kmlType == MappingCommon.KmlNormal:
            nnh = nnh + 1
    
    print "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (hitId, hit['kmlName'], kmlType, hit['reward'], hit['status'], hit['assignmentsRemaining'], hit['assignmentsAssigned'], hit['assignmentsPending'], hit['assignmentsCompleted'])
    found = False
    label = False
    for asgmtId, asgmt in sorted(hit['assignments'].iteritems()):
        found = True
        if not label:
            sys.stdout.write("Assign ID/Worker ID: %s/%s" % (asgmtId, asgmt['workerId']))
            label = True
        else:
            sys.stdout.write(", %s/%s" % (asgmtId, asgmt['workerId']))
    else:
        if found:
            print

print '\nAssignable HITs: %d; QAQC HITs: %d; FQAQC HITs: %d; non-QAQC HITs: %d; # total HITs: %d' % (nah, nqh, nfh, nnh, nh)
