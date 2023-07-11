from datetime import datetime
from MappingCommon import MappingCommon

mapc = MappingCommon()

now = str(datetime.today())
hits = mapc.getHitInfo()
nh = 0
nuh = 0
nfh = 0
for hitId, hit in sorted(hits.iteritems()):
    nh = nh + 1
    kmlType = hit['kmlType']
    if hit['status'] == 'Unassignable':
        nuh = nuh + 1
        if mapc.deleteFinalizedHit(hitId, now):
            nfh = nfh + 1
            print "delete_finalized_hits: hit %s has no remaining assignments and has been deleted\n" % hitId
        else:
            print "delete_finalized_hits: hit %s still has remaining assigned or pending assignments and cannot be deleted\n" % hitId

print "delete_finalized_hits deleted %s finalized HITs out of %s unassignable HITs out of a total of %s HITs" % (nfh, nuh, nh)
