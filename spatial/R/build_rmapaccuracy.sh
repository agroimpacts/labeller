#! /bin/bash
# update databases on an instance, for sandbox side only
if [ "${USER}" != "root" ]; then
    echo "$0 must be run from root user account"
    exit 1
fi

CWD=`pwd`
cd /home/mapper/labeller/spatial/R/rmapaccuracy
Rscript -e 'devtools::document()'
Rscript -e 'devtools::install(dependencies = FALSE)'
cd $CWD
