[Back to README](../README.md)

1) To get webob v1.2+ to be in Python's path, add a webob.pth file to the /usr/lib/<python>/site-packages directory with the name of the webob egg directory in it.

2) To easily access pgadmin3 v9.4, create /etc/profile.d/postgresql.[c]sh containing:
tcsh:
setenv PATH "/usr/pgsql-9.4/bin:$PATH"
bash:
export PATH="/usr/pgsql-9.4/bin:$PATH"

3) Add Apache http/https WSGI configurations for sandbox and mapper virtual hosts:
-see configuration file examples in the .../mapper/apache subdirectory.
-in particular, for each VirtualHost section in /etc/httpd/conf/httpd.conf and 
 /etc/httpd/conf.d/ssl.conf, pay special attention to the "Allow from" IP address ranges. 
 And note that each virtual host must be associated with one of the AWS VM's private IP addresses.

4) A Linux virtual interface will be needed for each apache virtual host. The first script
   (.../mapper/etc/ifcfg-eth0) should already exist in /etc/sysconfig/network-scripts. Compare
   it and make any changes that seem to be needed. This script usually uses DHCP and does not 
   need to have the primary private IP address for the VM listed in it.
   The second script (.../mapper/etc/ifcfg-eth0:1) should be copied to /etc/sysconfig/network-scripts,
   and its IPADDR value should be replaced with the VM's 1st secondary IP address.
   This is usually all that is needed, but sometimes other tweaks are required.

5) Append changes from the .../mapper/etc/aliases file into the system's aliases file.

6) Add the following lines to .bashrc for sandbox and mapper users:
source $HOME/mapper/common/bashrc_mapper.sh

NOTE: This allows MappingCommon.py to be imported from scripts running in 
      other than the .../mapper/common directory, during an *interactive* session.
      Cron daemons always need to run from the .../mapper/common directory
      because crontab ignores the .bashrc settings.
      Also defines the TF_* env vars needed by terraform.

7) This step is only needed if incoming emails need to be parsed and automatically processed.
   This is not currently the case.
   a) Build processmail by cd'ing to ~/mapper/processmail/src, and typing 'make' as user mapper or sandbox, and then 'make install' as root. This is necesary to process incoming emails from MTurk.
   b) Change permssions of ~/mapper/processmail directory: chmod o+rx ~/mapper/processmail

