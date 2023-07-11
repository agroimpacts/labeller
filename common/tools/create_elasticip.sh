#! /bin/bash
## Configure elastic IP address for instance

echo "This script will configure an elastic IP address for a named instance and"
echo "a named hosted zone"
# read -rsp $'Press any key to continue...\n' -n 1

INAME=$1
if [ -z "$INAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <zone_name>"
    exit 1
fi
ZONE=$2
if [ -z "$INAME" ]; then
    echo "`date`: Usage: $0 <instance_name> <zone_name>"
    exit 1
fi

# set up elastic IP address
echo "Configuring elastic IP for $INAME"
AID=`aws ec2 allocate-address --query 'PublicIp'`
IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`
echo $IID
NWID=`aws ec2 describe-instances --instance-ids $IID --filters --output text \
--query "Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId"`
echo $NWID

# assign private ip address to network work
aws ec2 assign-private-ip-addresses --network-interface-id $NWID \
--secondary-private-ip-address-count 1

# collect private IP address you just assigned
PIP=`aws ec2 describe-network-interfaces --filters \
--network-interface-ids $NWID --output text --query \
'NetworkInterfaces[*].PrivateIpAddresses[?Primary==\`false\`].PrivateIpAddress'`
echo $PIP

# associate primary elastic IP with instance
EIPASSOCI=`aws ec2 associate-address --public-ip \$AID --instance-id \$IID`

# hosted zone
HOSTEDZONE=`aws route53 list-hosted-zones-by-name --dns-name $ZONE \
--output text --query 'HostedZones[*].Id'`

# add record to hosted zone
ZONEPREFIX=$INAME  # choose name here
aws route53 change-resource-record-sets \
--hosted-zone-id $HOSTEDZONE --change-batch \
'{"Changes": [{"Action": "CREATE", "ResourceRecordSet": {"Name": "'$ZONEPREFIX'.'$ZONE'", "Type": "A", "TTL": 300, "ResourceRecords": [{ "Value": "'$AID'"}]}}]}'

# Start and stop the instance
echo "Stopping and restarting $INAME"
aws ec2 stop-instances --instance-ids $IID
