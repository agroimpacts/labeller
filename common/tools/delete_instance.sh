#! /bin/bash
read -p "Enter instance name to delete: " INAME
if [ -z "$INAME" ]; then
    printf '%s\n' "An instance name is needed"
    exit 1
fi

echo ""
echo "Are you sure you want to delete $INAME?"
select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done

IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`

VID=`aws ec2 describe-volumes --filters \
'Name=attachment.instance-id,Values='"$IID"'' --output text \
--query "Volumes[*].{ID:VolumeId}"`

echo $INAME "(Instance ID:" $IID") is being deleted"
aws ec2 terminate-instances --instance-ids $IID 

echo ""
echo "Do you want to delete $INAME's volume ($VID) also? "
select yn in "No" "Yes"; do
    case $yn in
        No ) exit;;
        Yes ) break;;
    esac
done

echo "Deleting volume $VID"
aws ec2 delete-volume --volume-id $VID 





