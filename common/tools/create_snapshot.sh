#! /bin/bash
## create a snapshot from an instance volume

INAME=$1
if [ -z "$INAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <snapshot_name>"
    exit 1
fi
SNAPNAME=$2
if [ -z "$SNAPNAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <snapshot_name>"
    exit 1
fi

# INAME=labeller2
# SNAPNAME=labeller2_final

IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

VID=`aws ec2 describe-volumes --filters \
'Name=attachment.instance-id,Values='"$IID"'' --output text \
--query "Volumes[*].{ID:VolumeId}"`

# SNAPID=`aws ec2 create-image --instance-id $IID --name "$AMINAME image" \
# --description "AMI of $INAME"`
SNAPID=`aws ec2 create-snapshot --volume-id $VID --description $SNAPNAME \
--tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value='$SNAPNAME'}]' \
--output text --query 'SnapshotId'`

DATE="$(date +%Y-%m-%Y%t%T)"
echo "Snapshot created for $INAME at $DATE" >> logs/create_snapshot.log
echo "Instance: $IID" >> logs/create_snapshot.log
echo "Volume: $VID" >> logs/create_snapshot.log
echo "Snapshot ID: $SNAPID" >> logs/create_snapshot.log
echo "" >> logs/create_snapshot.log

