#! /bin/bash
## create an AMI from a new instance

INAME=$1
if [ -z "$INAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <ami_name>"
    exit 1
fi
AMINAME=$2
if [ -z "$AMINAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <ami_name>"
    exit 1
fi


IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

AMIID=`aws ec2 create-image --instance-id $IID --name "$AMINAME image" \
--description "AMI of $INAME"`

echo $AMIID