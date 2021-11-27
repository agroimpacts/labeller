#! /bin/bash
## detect, build and load missing selinux module
## the default setting is to use existing .pp files in labeller/etc/ to authorize geopandas

# Must use root to run this bash
if [ "$USER" != "root" ]; then
    echo "Error: You must run $0 as root."
    exit
fi

# Get input parameters
MODULE_DIR=/home/mapper/labeller/etc
cd $MODULE_DIR
USE_EXISTING_MODULE=${1:-T}
MODULE_NAME=${2:-httpd_authorize_geopandas}

# remove built module if there's any
module -r $MODULE_NAME

if [ "$USE_EXISTING_MODULE" == F ]; then
    echo "Build selinux module and load the package"
    # set lelinux mode to be permissive
    sed -i "s/SELINUX=enforcing/SELINUX=permissive/gi" /etc/sysconfig/selinux
    # generate .pp file
    cat /var/log/audit/audit.log | audit2allow -M $MODULE_NAME
    cat /var/log/audit/audit.log | audit2allow -m $MODULE_NAME > ${MODULE_NAME}.te

    checkmodule -M -m -o ${MODULE_NAME}.mod ${MODULE_NAME}.te
    semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod
    semodule -i ${MODULE_NAME}.pp
    # set selinux back to enforcing mode
    sed -i "s/SELINUX=permissive/SELINUX=enforcing/gi" /etc/sysconfig/selinux
else
    echo "Load existing selinux package"
    checkmodule -M -m -o ${MODULE_NAME}.mod ${MODULE_NAME}.te
    semodule_package -o ${MODULE_NAME}.pp -m ${MODULE_NAME}.mod
    semodule -i ${MODULE_NAME}.pp
fi

# reboot system
echo "Finished setting up the selinux rule"
echo "Please allow severl minutes for system to reboot ..."
reboot

