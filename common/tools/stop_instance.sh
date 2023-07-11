#! /bin/bash
read -p "Enter instance name: " INAME
if [ -z "$INAME" ]; then
    printf '%s\n' "An instance name is needed"
    exit 1
fi

IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`
echo Stopping instance named $INAME with id $IID
aws ec2 stop-instances --instance-ids $IID
