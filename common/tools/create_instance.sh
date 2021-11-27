#! /bin/bash
## create instance from an AMI

AMIID=$1
if [ -z "$AMIID" ]; then
    echo "`date`: Usage: $0 <ami_id> <instance_type> <security_group> \
    <new_instance_name>"
    exit 1
fi
ITYPE=$2
if [ -z "$ITYPE" ]; then
    echo "`date`: Usage: $0 <ami_id> <instance_type> <security_group> \
    <new_instance_name>"
    exit 1
fi
SECGROUP=$3
if [ -z "$SECGROUP" ]; then
    echo "`date`: Usage: $0 <ami_id> <instance_type> <security_group> \
    <new_instance_name>"
    exit 1
fi
NEWINAME=$4
if [ -z "$NEWINAME" ]; then
    echo "`date`: Usage: $0 <ami_id> <instance_type> <security_group> \
    <new_instance_name>"
    exit 1
fi

# set up new instance
echo "Setting up new instance named $NEWINAME from AMI $AMIID"

VOLUMESIZE=${5:-AMISIZE}
if [ $VOLUMESIZE = "AMISIZE" ]; then
    echo "$NEWINAME will have same volume size as AMI"
    aws ec2 run-instances \
    --image-id $AMIID --count 1 --instance-type $ITYPE \
    --key-name airg-key-pair --security-groups $SECGROUP \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$NEWINAME'}]'
else 
    echo "$NEWINAME will have a $VOLUMESIZE GB volume"
    aws ec2 run-instances \
    --block-device-mapping DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUMESIZE} \
    --image-id $AMIID --count 1 --instance-type $ITYPE \
    --key-name airg-key-pair --security-groups $SECGROUP \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$NEWINAME'}]'
fi

BASEDIR=$(dirname "$0")
LOGFILE=$BASEDIR/logs/create_instance.log

NEWIID=`aws ec2 describe-instances \
--filters 'Name=tag:Name,Values='"$NEWINAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

echo $NEWIID

DATE="$(date +%Y-%m-%Y%t%T)"
echo "Instance $NEWINAME created from AMI $AMIID at $DATE" >> $LOGFILE
echo "Instance type: $ITYPE" >> $LOGFILE
echo "Security group: $SECGROUP" >> $LOGFILE
echo "Volume size: $VOLUMESIZE" >> $LOGFILE
echo "" >> $LOGFILE
