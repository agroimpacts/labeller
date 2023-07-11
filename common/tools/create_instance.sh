#! /bin/bash
## create an AMI from a new instance

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
aws ec2 run-instances --image-id $AMIID --count 1 --instance-type $ITYPE \
--key-name airg-key-pair --security-groups $SECGROUP \
--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$NEWINAME'}]'

NEWIID=`aws ec2 describe-instances \
--filters 'Name=tag:Name,Values='"$NEWINAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

echo $NEWIID