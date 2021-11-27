#! /bin/bash
read -p "Enter instance name: " INAME
if [ -z "$INAME" ]; then
    printf '%s\n' "An instance name is needed"
    exit 1
fi

IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

echo Starting instance named $INAME with id $IID
aws ec2 start-instances --instance-ids $IID
