#! /bin/bash
## Configure elastic IP address for instance

echo "This script gets the public IP address from a named instance and sshs"
echo "you into the instance as a particular user"
# read -rsp $'Press any key to continue...\n' -n 1

INAME=$1
if [ -z "$INAME" ]; then
echo "`date`: Usage: $0 <instance_name> <user_name>"
exit 1
fi

UNAME=$2
if [ -z "$UNAME" ]; then
echo "`date`: Usage: $0 <instance_name> <user_name>"
exit 1
fi
#echo "Getting public IP for $INAME"
IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[].Instances[][PublicIpAddress]'`

echo "Logging into" $IID "as user" $UNAME
ssh $UNAME@$IID