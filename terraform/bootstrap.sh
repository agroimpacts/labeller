#!/bin/bash

RPM_URI=$(echo $1 | sed 's,/$,,')
NB_BUCKET=$(echo $2 | sed 's,s3://\([^/]*\).*,\1,')
NB_PREFIX=$(echo $2 | sed 's,s3://[^/]*/,,' | sed 's,/$,,')
GEOPYSPARKJARS=$3
GEOPYSPARKURI=$4
RASTERFRAMESSHA=$5
RASTERFRAMES_VERSION=$6

# Parses a configuration file put in place by EMR to determine the role of this node
is_master() {
  if [ $(jq '.isMaster' /mnt/var/lib/info/instance.json) = 'true' ]; then
    return 0
  else
    return 1
  fi
}

if is_master; then

    # Download packages
    mkdir -p /tmp/blobs/
    aws s3 sync $RPM_URI /tmp/blobs/

    # Install binary packages
    (cd /tmp/blobs; sudo yum localinstall -y gdal213-2.1.3-33.x86_64.rpm hdf5-1.8.20-33.x86_64.rpm netcdf-4.5.0-33.x86_64.rpm nodejs-8.5.0-13.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm configurable-http-proxy-0.0.0-13.x86_64.rpm)

    # Install Python packages
    sudo pip-3.4 install --upgrade pip
    sudo ln -s /usr/local/bin/pip3 /usr/bin/
    sudo ln -s /usr/local/bin/pip3.4 /usr/bin/
    (cd /tmp/blobs ; sudo pip3.4 install *.whl)
    sudo -E env PATH="/usr/local/bin:$PATH" pip3 install --upgrade 'rasterio==1.0.3'

    # Install Git so we can clone learner
    sudo apt-get install -y git
    
    # Linkage
    echo '/usr/local/lib' > /tmp/local.conf
    echo '/usr/local/lib64' >> /tmp/local.conf
    sudo cp /tmp/local.conf /etc/ld.so.conf.d/local.conf
    sudo ldconfig
    rm -f /tmp/local.conf

    # Install GeoPySpark
    if [[ $GEOPYSPARKURI == s3* ]]; then
	aws s3 cp $GEOPYSPARKURI /tmp/geopyspark.zip
	GEOPYSPARKURI=/tmp/geopyspark.zip
    fi
    sudo -E env "PATH=/usr/local/bin:$PATH" pip3.4 install "$GEOPYSPARKURI"
    sudo -E env "PATH=/usr/local/bin:$PATH" jupyter nbextension enable --py widgetsnbextension --system
    sudo mkdir -p /opt/jars/
    for url in $(echo $GEOPYSPARKJARS | tr , "\n")
    do
	if [[ $url == s3* ]]; then
	    (cd /opt/jars ; sudo aws s3 cp $url . )
	else
	    (cd /opt/jars ; sudo curl -L -O -C - $url )
	fi
    done

    # Set up user account to manage JupyterHub
    sudo groupadd shadow
    sudo chgrp shadow /etc/shadow
    sudo chmod 640 /etc/shadow
    # sudo usermod -a -G shadow hadoop
    sudo useradd -G shadow -r hublauncher
    sudo groupadd jupyterhub
    sudo useradd -m -G jupyterhub,hadoop jupyteruser
    echo "jupyteruser:jhpasswd" | sudo chpasswd

    # Ensure that all members of `jupyterhub` group may log in to JupyterHub
    echo 'hublauncher ALL=(%jupyterhub) NOPASSWD: /usr/local/bin/sudospawner' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(ALL) NOPASSWD: /usr/sbin/useradd' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(ALL) NOPASSWD: /bin/chown' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(ALL) NOPASSWD: /bin/mkdir' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(ALL) NOPASSWD: /bin/mv' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(hdfs) NOPASSWD: /usr/bin/hdfs' | sudo tee -a /etc/sudoers

    # Environment setup
    cat <<EOF > /tmp/oauth_profile.sh
export AWS_DNS_NAME=$(aws ec2 describe-network-interfaces --filters Name=private-ip-address,Values=$(hostname -i) | jq -r '.[] | .[] | .Association.PublicDnsName')
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3.4
export PYSPARK_PYTHON=/usr/bin/python3.4
export SPARK_HOME=/usr/lib/spark
export PYTHONPATH=/usr/lib/spark/python/lib/pyspark.zip:/usr/lib/spark/python/lib/py4j-0.10.4-src.zip
export GEOPYSPARK_JARS_PATH=/opt/jars

alias launch_hub='sudo -u hublauncher -E env "PATH=/usr/local/bin:$PATH" jupyterhub --JupyterHub.spawner_class=sudospawner.SudoSpawner --SudoSpawner.sudospawner_path=/usr/local/bin/sudospawner --Spawner.notebook_dir=/home/{username}'
EOF
    sudo mv /tmp/oauth_profile.sh /etc/profile.d
    . /etc/profile.d/oauth_profile.sh

    # Set up hadoop's jupyter configs to use notebooks off S3
    cat << LOL > /tmp/nbconf.py
from s3contents import S3ContentsManager

c.NotebookApp.contents_manager_class = S3ContentsManager
c.S3ContentsManager.bucket = "$NB_BUCKET"
c.S3ContentsManager.prefix = "$NB_PREFIX"

LOL

    sudo -u jupyteruser mkdir /home/jupyteruser/.jupyter/
    sudo -u jupyteruser cp /tmp/nbconf.py /home/jupyteruser/.jupyter/jupyter_notebook_config.py

    # Setup jupyterhub system configs
    cat <<EOF > /tmp/jupyterhub_config.py
c = get_config()

c.JupyterHub.spawner_class='sudospawner.SudoSpawner'
c.SudoSpawner.sudospawner_path='/usr/local/bin/sudospawner'
c.Spawner.notebook_dir='/home/{username}'

EOF

    # Install GeoPySpark kernel
    cat <<EOF > /tmp/kernel.json
{
    "language": "python",
    "display_name": "GeoPySpark",
    "argv": [
        "/usr/bin/python3.4",
        "-m",
        "ipykernel",
        "-f",
        "{connection_file}"
    ],
    "env": {
        "PYSPARK_PYTHON": "/usr/bin/python3.4",
        "PYSPARK_DRIVER_PYTHON": "/usr/bin/python3.4",
        "SPARK_HOME": "/usr/lib/spark",
        "PYTHONPATH": "/usr/lib/spark/python/lib/pyspark.zip:/usr/lib/spark/python/lib/py4j-0.10.4-src.zip",
        "GEOPYSPARK_JARS_PATH": "/opt/jars",
        "YARN_CONF_DIR": "/etc/hadoop/conf",
        "PYSPARK_SUBMIT_ARGS": "--conf hadoop.yarn.timeline-service.enabled=false --packages io.astraea:pyrasterframes_2.11:${RASTERFRAMES_VERSION} --repositories https://repo.locationtech.org/content/repositories/sfcurve-releases, pyspark-shell"
    }
}
EOF
    sudo mkdir -p /usr/local/share/jupyter/kernels/geopyspark
    sudo cp /tmp/kernel.json /usr/local/share/jupyter/kernels/geopyspark/kernel.json
    rm -f /tmp/kernel.json

    # Install pyrasterframes
    curl -L -o /tmp/rasterframes.zip https://github.com/geotrellis/rasterframes/archive/${RASTERFRAMESSHA}.zip && \
    unzip -d /tmp /tmp/rasterframes.zip && \
    sed -i 's|"boundless-releases" at "https://repo.boundlessgeo.com/main/"|"osgeo-snapshots" at "https://repo.osgeo.org/repository/snapshot/",\n      "osgeo-releases" at "https://repo.osgeo.org/repository/release/"|' /tmp/rasterframes-${RASTERFRAMESSHA}/project/ProjectPlugin.scala && \
    sudo -E env "PATH=/usr/local/bin:$PATH" pip3.4 install /tmp/rasterframes-${RASTERFRAMESSHA}/pyrasterframes/python && \
    pushd /tmp/rasterframes-${RASTERFRAMESSHA}/ && \
    curl -L -o ./sbt https://raw.githubusercontent.com/paulp/sbt-extras/master/sbt && \
    chmod +x ./sbt && \
    sudo yum install -y git && \
    sudo -u jupyteruser ./sbt pyrasterframes/spPublishLocal && \
    sudo -u jupyteruser ln -s /home/jupyteruser/.ivy2/local/io.astraea/pyrasterframes /home/jupyteruser/.ivy2/local/io.astraea/pyrasterframes_2.11 && \
    sudo -u jupyteruser ln -s /home/jupyteruser/.ivy2/local/io.astraea/pyrasterframes_2.11/${RASTERFRAMES_VERSION}/jars/pyrasterframes.jar /home/jupyteruser/.ivy2/local/io.astraea/pyrasterframes_2.11/${RASTERFRAMES_VERSION}/jars/pyrasterframes_2.11.jar && \
    popd && \
    sudo rm -rf /tmp/rasterframes.zip /tmp/rasterframes-${RASTERFRAMESSHA}

    # Make Scala packages available to hadoop
    sudo cp -r ~jupyteruser/.ivy2 ~hadoop
    sudo chown -R hadoop:hadoop ~/.ivy2

    # Install extra software
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install python3-devel
    sudo yum -y install postgresql-devel
    sudo pip3 install psycopg2-binary

    # Execute
    cd /tmp
    sudo -u hublauncher -E env "PATH=/usr/local/bin:$PATH" jupyterhub --JupyterHub.spawner_class=sudospawner.SudoSpawner --SudoSpawner.sudospawner_path=/usr/local/bin/sudospawner --Spawner.notebook_dir=/home/{username} -f /tmp/jupyterhub_config.py &

else
    # Download packages
    mkdir -p /tmp/blobs/
    aws s3 sync $RPM_URI /tmp/blobs/

    # Install packages
    (cd /tmp/blobs; sudo yum localinstall -y gdal213-2.1.3-33.x86_64.rpm hdf5-1.8.20-33.x86_64.rpm netcdf-4.5.0-33.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm)

    # Install Python packages
    sudo pip-3.4 install --upgrade pip
    sudo ln -s /usr/local/bin/pip3 /usr/bin/
    sudo ln -s /usr/local/bin/pip3.4 /usr/bin/
    (cd /tmp/blobs ; sudo pip3.4 install *.whl)
    sudo -E env PATH="/usr/local/bin:$PATH" pip3 install --upgrade 'rasterio==1.0.3'

    # Install GeoPySpark
    if [[ $GEOPYSPARKURI == s3* ]]; then
	aws s3 cp $GEOPYSPARKURI /tmp/geopyspark.zip
	GEOPYSPARKURI=/tmp/geopyspark.zip
    fi
    sudo -E env "PATH=/usr/local/bin:$PATH" pip3.4 install "$GEOPYSPARKURI"

    # Install pyrasterframes
    curl -L -o /tmp/rasterframes.zip https://github.com/geotrellis/rasterframes/archive/${RASTERFRAMESSHA}.zip && \
    unzip -d /tmp /tmp/rasterframes.zip && \
    sed -i 's|"boundless-releases" at "https://repo.boundlessgeo.com/main/"|"osgeo-snapshots" at "https://repo.osgeo.org/repository/snapshot/",\n      "osgeo-releases" at "https://repo.osgeo.org/repository/release/"|' /tmp/rasterframes-${RASTERFRAMESSHA}/project/ProjectPlugin.scala && \
    sudo pip3 install /tmp/rasterframes-${RASTERFRAMESSHA}/pyrasterframes/python && \
    rm -rf /tmp/rasterframes.zip /tmp/rasterframes-${RASTERFRAMESSHA}

    # Install extra software
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install python3-devel
    sudo yum -y install postgresql-devel
    sudo pip3 install psycopg2-binary

    # Clone Learner tip of devel branch without git history. This is secret and should be removed once open sourced
    git clone --depth 1 -b master https://github.com/agroimpacts/learner.git /home/hadoop/learner/

    # Linkage
    echo '/usr/local/lib' > /tmp/local.conf
    echo '/usr/local/lib64' >> /tmp/local.conf
    sudo cp /tmp/local.conf /etc/ld.so.conf.d/local.conf
    sudo ldconfig
    rm -f /tmp/local.conf
fi
