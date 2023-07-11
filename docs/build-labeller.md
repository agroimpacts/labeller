Building labeller from scratch
================

  - [Introduction](#introduction)
  - [Launch a new instance](#launch-a-new-instance)
  - [Configuration](#configuration)
      - [ssh access](#ssh-access)
      - [New users name and password](#new-users-name-and-password)
      - [Installs](#installs)
          - [python 2.7](#python-2.7)
          - [`postgres`](#postgres)
          - [postgis](#postgis)
              - [The `yum` approach](#the-yum-approach)
              - [Building from source](#building-from-source)
                  - [GEOS](#geos)
                  - [libkml](#libkml)
                  - [gdal 2.2.3](#gdal-2.2.3)
                  - [Finally, postgis](#finally-postgis)
                      - [Resolution steps](#resolution-steps)
      - [Other software](#other-software)
          - [R 3.4.0](#r-3.4.0)
          - [python](#python)
          - [Bring in `labeller` code
            base](#bring-in-labeller-code-base)
      - [Configure database](#configure-database)
          - [Setting up the database](#setting-up-the-database)
              - [Set up pg\_hba.conf](#set-up-pg_hba.conf)
              - [Create database](#create-database)
                  - [Create from scratch](#create-from-scratch)
                  - [Using existing scripts and
                    database](#using-existing-scripts-and-database)
                      - [aws cli](#aws-cli)
                      - [phpPgAdmin](#phppgadmin)
                      - [Restore database](#restore-database)
                      - [Set up \~/.pgpass](#set-up-.pgpass)
          - [Port configuration](#port-configuration)
      - [Setting up `labeller`’s code
        base](#setting-up-labellers-code-base)
          - [Getting the webapp running](#getting-the-webapp-running)
              - [permissions](#permissions)
              - [yum installs](#yum-installs)
              - [selinux changes](#selinux-changes)
              - [Set up an elastic IP](#set-up-an-elastic-ip)
                  - [certbot](#certbot)
                  - [Continue to populate
                    config.yaml](#continue-to-populate-config.yaml)

# Introduction

Directions for how to build a brand new instance of `labeller` on a
fresh AWS EC2 instance.

This assumes that you already have an AWS account, a locally configured
AWS CLI, and permissions to create a new instance, as well as a key-pair
.pem file.

# Launch a new instance

The following sets up a new instance of 50GB size using an existing
security group that is fairly locked down to certain IP addresses. It is
a t2.large running the latest RedHat instance, and additional has
instance-level permissions that allow it to read and write to our s3
bucket.

Note that the AMI listed here is now a community AMI owned by Redhat
because AWS provides RHEL8 as the default to install now.

``` bash
AMIID=ami-9e2f0988  # RHEL 7.3
ITYPE=t2.large
KEYNAME=mapper_key_pair
SECURITY=airg-security
INAME=labeller
OWNER=airg
SDASIZE=50
IAM=activemapper_planet_readwriteS3

aws ec2 run-instances --image-id $AMIID --count 1 --instance-type $ITYPE --iam-instance-profile Name=$IAM --key-name $KEYNAME --security-groups $SECURITY  --block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": $SDASIZE } } ]" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$INAME'}]' 'ResourceType=volume,Tags=[{Key=Owner,Value='$OWNER'}]' 
```

Once it is spinning log in with the relevant key name that was specified
to launch it. The script below allows you to get the public IP address
automatically based on the instance name, and then ssh in to the
instance.

``` bash
IP=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].PublicIpAddress'`
echo $IP

ssh -i "key_name.pem" ec2-user@$IP
```

-----

<p align="center">

[Back to top](#introduction) || [Back to **index**](../README.md)

</p>

-----

# Configuration

## ssh access

Once we the new instance, add your public key to the instance for easier
ssh access:

From local machine

``` bash
pbcopy < ~/.ssh/id_rsa.pub 
```

And then on instance use vim to paste the key into authorized keys

``` bash
vi ~/.ssh/authorized_keys
```

## New users name and password

Add users mapper and sandbox. From root (accessed through ec-2user)

``` bash
useradd mapper
passwd mapper
#usersadd sandbox
#passwd sandbox
```

Entered the new passwords, and stored in password manager.

Create a new user group, labeller, and add all users to group

``` bash
groupadd labeller
usermod -a -G labeller mapper
#usermod -a -G labeller sandbox
usermod -a -G labeller ec2-user
```

Then allow ssh access for these users

``` bash
vi /etc/ssh/sshd_config
```

And at bottom add line “AllowGroups root labeller”

Then from root `systemctl restart sshd`

Had to add ssh configurations to each user, of course. From root:

``` bash
sudo su - mapper
cd /home/mapper
mkdir .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
vi .ssh/authorized_keys
```

And then copy in the public key from local machines, which is obtained
by doing `pbcopy < ~/.ssh/id_rsa.pub` on the local machine.

Steps above were done for user sandbox as well.

## Installs

Initial installs

``` bash
yum install vim  # to use vim instead of vi
yum install swig  # source build of geos seemed to demand it, but broke build
yum install wget 
yum install git
yum install screen
```

### python 2.7

`labeller` was built on python 2.7, so we need to stick with it for now.
Fortunately, on the RHEL7 AMI installed above, it is the default
`python`, and nothing else needs to be done. You will need to install
`pip2` though, which is covered below, but could also be done at this
stage.

### `postgres`

Got to [here](https://www.postgresql.org/download/linux/redhat/), and
followed instructions for installing postgres9.4, using dropdown boxes.
Doing this from root (ssh’d in ec2-user, and then `sudo bash`).

``` bash
yum install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install postgresql94
yum install postgresql94-server
yum install postgresql94-devel 
```

\[Note: the install of devel was done after postgis install of source
asked for it\]

And also ran the optional arguments to autostart

``` bash
/usr/pgsql-9.4/bin/postgresql94-setup initdb
systemctl enable postgresql-9.4
systemctl start postgresql-9.4
```

Check that is running with `ps -ef | grep postgres`, and there will be
about 7 lines returned. But stop it for now while other installs are
done

``` bash
systemctl stop postgresql-9.4
```

### postgis

Have to install various dependencies first, and need some basics,
according to
[here](https://postgis.net/docs/manual-2.5/postgis_installation.html#install_requirements),
which include `gcc`, `gmake`, and `gdal`, etc. According to
[here](http://www.postgresonline.com/journal/archives/362-An-almost-idiots-guide-to-install-PostgreSQL-9.5,-PostGIS-2.2-and-pgRouting-2.1.0-with-Yum.html)
though, the EPEL repository provides `gdal` and friends, so we run just
the first two below, but in practice I ended up with the other three:

``` bash
yum install gcc
yum install make
yum install cmake
yum install bzip2  # neceessary for upgrade of GEOS later on
yum install gcc-c++  # necessary for building GEOS, otherwise g++ cmd not found
```

#### The `yum` approach

This was the initial attempt used, and the process of working through it
might have interacted with the subsequent source approach I end up
using, so it is preserved here.

And then, to get the EPEL repository, I followed these
[directions](https://fedoraproject.org/wiki/EPEL):

``` bash
yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch
```

I also tried the recommended optional for RHEL7:

``` bash
subscription-manager repos --enable "rhel-*-optional-rpms" --enable "rhel-*-extras-rpms"  --enable "rhel-ha-for-rhel-*-server-rpms"
```

But that failed. I tried a solution
[here](https://access.redhat.com/discussions/3327311), which suggested
these steps:

``` bash
sudo subscription-manager remove --all
sudo subscription-manager unregister
sudo subscription-manager clean
sudo subscription-manager register
sudo subscription-manager refresh
sudo subscription-manager attach --auto
sudo subscription-manager repos --enable rhel-7-server-extras-rpms
sudo subscription-manager repos --enable rhel-7-server-optional-rpms
sudo subscription-manager repos --enable rhel-server-rhscl-7-rpms
```

But the `register` command stopped me because I haven’t registered on
RHEL. So I just went ahead with this:

``` bash
yum install postgis2_94
```

And it installed everything, but it has `gdal` 1.11.

So I did `yum remove` on `postgis`, `gdal`, `geos`, etc after stopping
`postgres`, so I can build things from source. First I stopped
`postgres`:

``` bash
service postgresql-9.4 stop
```

#### Building from source

Since I decided not to install `postgis` with `yum` because of
dependencies, because of the above issues, I moved to a source based
approach, so I started with the various dependencies, which were built
from an `installs` directory under `/home/ec2-user`

``` bash
mkdir installs
cd installs/
```

Following original wiki from `mapperAL` for installing upgraded/specific
version of gdal, geos, etc, which we are doing to reproduce specific
installs. We need to allow Sources will install into `/usr/local`, so to
allow centrally installed libraries and the postgresql server to find
these manually-built libs, do the following:

> As root, create file /etc/ld.so.conf.d/usr\_local\_lib.conf containing
> this one line: ‘/usr/local/lib’ (without the quotes)

> Run the ‘ldconfig’ command to rebuild the library cache.

Here is how it was done:

``` bash
printf '/usr/local/lib' > /etc/ld.so.conf.d/usr_local_lib.conf
ldconfig
```

##### GEOS

``` bash
wget http://download.osgeo.org/geos/geos-3.6.2.tar.bz2
tar -xvjf geos-3.6.2.tar.bz2
cd geos-3.6.2
./configure --enable-python 2>&1 | tee configure.out
make -j4  2>&1 | tee make.out
make install 2>&1 | tee make_install.out
```

This didn’t install properly, after the fact, so I ran `yum install
geos36`, which forced install of `geos37`

Add back in libspatialite. First find the rpm for it,
[here](http://rpm.pbone.net), which gives a link to the rpm to download.

``` bash
wget ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/Packages/l/libspatialite-4.1.1-2.el7.x86_64.rpm
rpm -Uvh --nodeps libspatialite-4.1.1-2.el7.x86_64.rpm
#wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/chaudhari:/forked/RHEL_7/x86_64/libspatialite-devel-4.3.0a-4.2.x86_64.rpm
#rpm -Uvh --nodeps libspatialite-devel-4.3.0a-4.2.x86_64.rpm  #
```

\[Note: I installed the wrong libspatialite-devel, see R install section
for fix\]

##### libkml

Installing libkml required many dependencies. This was how I got it to
work.

``` bash
# dependencies for libkml
wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/matthewdva:/build:/RedHat:/RHEL-7/complete/x86_64/cpptest-1.1.1-9.el7.x86_64.rpm

wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/matthewdva:/build:/RedHat:/RHEL-7/complete/x86_64/uriparser-0.7.5-9.el7.x86_64.rpm

wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/matthewdva:/build:/RedHat:/RHEL-7/complete/x86_64/minizip-1.2.7-13.el7.x86_64.rpm

yum install cpptest-1.1.1-9.el7.x86_64.rpm
yum install uriparser-0.7.5-9.el7.x86_64.rpm
yum install minizip-1.2.7-13.el7.x86_64.rpm
```

But there were problems with protected zlibs when installing minizip, so
trieda full `yum update`. But then had to downgrade `zlib`, but
downgrading still brought up zlib conflict, so, what I simply ended up
doing was remove .i686 version of zlib, and then installing right rpm
for zlib.

``` bash
yum remove zlib-1.2.7-13.el7.i686

wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home%3A/matthewdva%3A/build%3A/RedHat%3A/RHEL-7/complete/x86_64/zlib-1.2.7-13.el7.x86_64.rpm
yum downgrade zlib-1.2.7-13.el7.x86_64.rpm 
```

After than `minizip` installed, and I could install `libkml`

``` bash
# Finally, this worked
yum install minizip-1.2.7-13.el7.x86_64.rpm

# Then libkml will install
wget https://cbs.centos.org/kojifiles/packages/libkml/1.3.0/3.el7/x86_64/libkml-1.3.0-3.el7.x86_64.rpm
yum install libkml-1.3.0-3.el7.x86_64.rpm

wget https://cbs.centos.org/kojifiles/packages/libkml/1.3.0/3.el7/x86_64/libkml-devel-1.3.0-3.el7.x86_64.rpm
yum install libkml-devel-1.3.0-3.el7.x86_64.rpm
```

##### gdal 2.2.3

After having this done, I tried doing a `yum install gdal23`, but it was
giving errors with missing `gpsbabel` and `libspatialite` errors, so I
went and did the source install of `gdal`.

``` bash
wget http://download.osgeo.org/gdal/2.2.3/gdal-2.2.3.tar.gz
tar -xvzf gdal-2.2.3.tar.gz
cd gdal-2.2.3
./configure --prefix=/usr/bin --with-sqlite3 --with-spatialite --with-libkml --with-armadillo --with-python 2>&1 | tee configure.out
make -j4  2>&1 | tee make.out
make install 2>&1 | tee make_install.out
```

To get `sf` to install correctly in `R` (below), we also had to add
environmental variable for GDAL\_DATA, which:

``` bash
cd /home/ec2_user
sed -i '$ a export GDAL_DATA=/usr/share/gdal' .bash_profile
source .bash_profile
```

Under previous version of `mapper`, we also built it with the flags
`--with-netcdf --with-hdf5 --with-hdf4`, but since we don’t touch those
file formats in mapper, I didn’t build with those. Note also the
addition of the `--prefix=/usr/bin`, which I found suggested as a
[solution](https://stackoverflow.com/questions/54431511/having-trouble-installing-rgdal-and-gdal-on-centos)
for a bug I got, which was this:

``` bash
ogr_sfcgal.h:34:34: fatal error: SFCGAL/capi/sfcgal_c.h: No such file or directory
```

SFCGAL (1.3.1-1.rhel7) was already installed, but

    yum install SFCGAL-devel*

Got me past that error. I hit another one though, which was:

``` bash
extensions/gdal_wrap.cpp:173:21: fatal error: Python.h: No such file or directory
```

The solution was
[here](https://unix.stackexchange.com/questions/275627/how-to-compile-c-extension-for-python/275636),
which was to install `python-dev`:

``` bash
yum install python-devel.x86_64
```

After repeating again `make install 2>&1 | tee make_install.out`, I was
able to get a successful build, but per
[here](%5Bsolution%5D\(https://stackoverflow.com/questions/54431511/having-trouble-installing-rgdal-and-gdal-on-centos\)),
running `gdalinfo` gave me a:

    gdalinfo: error while loading shared libraries: libgdal.so.20: cannot open shared object file: No such file or directory

So running `ldconfig` per that solution solve it. `gdal` seems
functional.

##### Finally, postgis

The source install worked, after various dependencies had to be figured,
which were these pre-installs:

A `libxml2` issue has to be first resolved, with specific `zlib-devel`
install

``` bash
wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home%3A/matthewdva%3A/build%3A/RedHat%3A/RHEL-7/standard/x86_64/zlib-devel-1.2.7-13.el7.x86_64.rpm
yum install zlib-devel-1.2.7-13.el7.x86_64.rpm 
yum install libxml2-devel
```

This worked with the configuration step as written:

``` bash
wget http://postgis.net/stuff/postgis-2.4.3.tar.gz
tar -xvzf postgis-2.4.3.tar.gz
cd postgis-2.4.3
#./configure --with-pgconfig="/usr/pgsql-9.4/bin/pg_config" 2>&1 | tee configure.out
./configure --with-geosconfig="/usr/geos37/bin/geos-config" --with-projdir="/usr/proj49/" --with-pgconfig="/usr/pgsql-9.4/bin/pg_config" 2>&1 | tee configure.out
make -j4  2>&1 | tee make.out
make install 2>&1 | tee make_install.out
```

###### Resolution steps

I first used the commented out configure line, which led me to the
sequence of steps to solve it:

``` bash
./configure --with-pgconfig="/usr/pgsql-9.4/bin/pg_config" 2>&1 | tee configure.out
#<snip>
configure: error: could not find xml2-config from libxml2 within the current path. You may need to try re-running configure with a --with-xml2config parameter.
```

Needed to try install `libxml2-devel`, but `yum install libxml2-devel`
gave error:

``` bash
Protected multilib versions: zlib-1.2.7-18.el7.x86_64 != zlib-1.2.7-13.el7.i686
```

So needed very specific zlib-devel to solve it:

``` bash
wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home%3A/matthewdva%3A/build%3A/RedHat%3A/RHEL-7/standard/x86_64/zlib-devel-1.2.7-13.el7.x86_64.rpm
yum install zlib-devel-1.2.7-13.el7.x86_64.rpm 
```

And then this worked:

``` bash
yum install libxml2-devel
```

The second try at running `.configure`:

``` bash
configure: error: could not find geos-config within the current path. You may need to try re-running configure with a --with-geosconfig parameter.
```

That needed `geos-devel` installed:

``` bash
yum install geos37-devel.x86_64
```

Had to find path to geos-config to specify path for configuring.

``` bash
rpm -ql geos37-devel | grep geos-config
```

So could add that path as a parameter:

``` bash
./configure --with-geosconfig="/usr/geos37/bin/geos-config" --with-pgconfig="/usr/pgsql-9.4/bin/pg_config" 2>&1 | tee configure.out
```

It complained about not finding `proj_api.h`, so I found it with `ls`,
and added it, and this was the winning combination:

``` bash
yum install proj49-devel.x86_64 
./configure --with-geosconfig="/usr/geos37/bin/geos-config" --with-projdir="/usr/proj49/" --with-pgconfig="/usr/pgsql-9.4/bin/pg_config" 2>&1 | tee configure.out
```

## Other software

Before creating the databases and importing the code base, we will add
the other software in the versions that were installing in the most
recent working build of `mapper`.

Already installed: - `postgres 9.4.12` - postgis 2.4.3 r16312 - GEOS
3.7.1, instead of 3.6.2 - GDAL 2.2.3 - proj4 4.9.3, instead of 4.8.0

Now we’ll move to R and necessary packages

### R 3.4.0

To get R, I followed these
[instructions](https://blog.sellorm.com/2017/11/11/basic-installation-of-r-on-redhat-linux-7/),
but I started here, not installing `libxml2` because I already had it:

``` bash
yum install -y libcurl-devel openssl-devel # libxml2-devel
```

Before this, which was the recommended first step (it didn’t work at
first because the single quotes were formatted badly on pasting):

``` bash
yum groupinstall -y 'Development Tools'
```

And then:

``` bash
yum install -y epel-release  # didn't work at first, so:
rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
# Then redoing it seemed to work
yum install -y epel-release
```

That gives `R3.6.0` as the option, so I am going to take a chance with
it, but I found on rpmbone an rpm for 3.4.0

``` bash
cd installs/
wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/matthewdva:/build:/EPEL:/el7/RHEL_7/x86_64/R-core-3.4.0-2.el7.x86_64.rpm
```

``` bash
yum install -y R
```

This gave some errors, which is mainly missing `pcre2-devel` and
`texinfo-tex`, but also persistent `libspatialite-devel` missing the
relevant `libspatial.so.7` library, so I found the I hadn’t installed
\`libspatialite itself, and I had 4.3.0 of *devel* but only 4.1.1 came
through on the EPEL repo. So, I remove the 4.3.0 devel, and did this to
fix:

``` bash
yum install libspatialite  
wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home%3A/matthewdva%3A/build%3A/EPEL%3A/el7/RHEL_7/x86_64/libspatialite-devel-4.1.1-2.el7.x86_64.rpm
yum install libspatialite-devel-4.1.1-2.el7.x86_64.rpm 
```

So I have reinstalled the right devel version to be safe. Note that this
back installed proj4.8, so I have two projs now.

Trying to reinstall R, I still had those errors, but the instructions
gave the solution:

``` bash
yum --enablerepo=rhel-optional install -y R
```

But the “rhel-optional” wasn’t right, so per instructions I got the
right answer using:

``` bash
`grep -i ^'\[.*optional' /etc/yum.repos.d/*`
```

And then:

``` bash
yum --enablerepo=rhui-REGION-rhel-server-optional install -y R
```

Seems to work now. These packages were on original `mapper`:

  - sf\_0.6-2, RPostgreSQL\_0.6-2, raster\_2.6-7, sp\_1.2-7,
    dplyr\_0.7.6, aws.s3\_0.3.12, data.table\_1.11.4, DBI\_1.0.0,
    units\_0.6-0

But opted to install the most up to date versions instead (and hope
nothing breaks). From R console

``` r
# usage
pkgs <- c("sf", "lwgeom", "RPostgreSQL", "devtools",  "raster", "rgdal"
          "dplyr", "dbplyr", "aws.s3", "data.table", "DBI", "units",
          "fasterize")
install(pkgs)
```

Most likely breakages are with `sf`. Alternatively, `rmapaccuracy` could
be installed with `dependencies = TRUE` when the codebase is installed.

`sf` did fail, as did `udunits`, etc, so adapted instructions from
previous wiki, but upgrading to `udunits2-2.26`. Also, the default
install was into /usr/local/lib, and subsequent R package installs
failed. The below worked. Some instructions for units were found
[here](https://www.unidata.ucar.edu/software/udunits/udunits-current/doc/udunits/udunits2.html).

``` r
udunits_dir <- "/home/ec2-user/installs/udunits"
system(paste0("mkdir ", udunits_dir))
system(paste0("wget --directory-prefix=", udunits_dir, 
              #" ftp://ftp.unidata.ucar.edu/pub/udunits/udunits-2.2.25.tar.gz"))
              " ftp://ftp.unidata.ucar.edu/pub/udunits/udunits-2.2.26.tar.gz"))
owd <- getwd()
setwd(udunits_dir)
# system("tar xzvf udunits-2.2.25.tar.gz")
system("tar xzvf udunits-2.2.26.tar.gz")
# setwd(file.path(udunits_dir, "udunits-2.2.26"))
system("./configure prefix='/usr'")
system("make")
system("make install")
setwd(owd)
args1 <- c("--with-udunits2-include=/usr/include/udunits2", 
           "--with-udunits2-lib=/usr/bin/udunits2")
install.packages("udunits2", type = "source", configure.args = args1,
                 repos = "http://cran.rstudio.com")
install.packages("units", repos = "http://cran.rstudio.com")

# fails, even after initial configuration
args2 <- c("--with-gdal-config=/usr/bin/gdal-config", 
           "--with-geos-config=/usr/geos37/bin/geos-config")
install.packages("sf", configure.args = args2)
```

The `sf` part failed with a warning that it couldn’t find `gcs.csv`,
something about GDAL\_DATA path. So I did this.

``` bash
sed -i '$ a export GDAL_DATA=/usr/share/gdal' .bash_profile
source .bash_profile
```

`Sys.getenv()` in `R` showed that `R` wasn’t picking up the environment
variable. So I went to install `rgdal` next. It had problems finding the
proj library, due to the rpm sticking it in /usr/proj49 instead of
/usr/bin/proj49. Modifying the solution
[here](https://gis.stackexchange.com/questions/203991/errors-installing-rgdal-on-linux-system)
worked.

``` r
args2 <- c("--with-proj-include=/usr/proj49/include", 
           "--with-proj-lib=/usr/proj49/lib")
install.packages("rgdal", configure.args = args2)
```

I then tried to install `sf` again (last set of arguments in `sf`
install block), and it gave a new error:

``` bash
Error: proj/epsg not found
Either install missing proj support files, for example
the proj-nad and proj-epsg RPMs on systems using RPMs,
or if installed but not autodetected, set PROJ_LIB to the
correct path, and if need be use the --with-proj-share=
configure argument.
```

So try this:

``` r
# install sf (this will fail if GDAL_DATA is not set for gdal)
args2 <- c("--with-gdal-config=/usr/bin/gdal-config", 
           "--with-geos-config=/usr/geos37/bin/geos-config", 
           "--with-proj-share=/usr/proj49/share")
install.packages("sf", configure.args = args2)
```

Got the same error, so it seemed as if, looking in `/usr/proj49/share`,
that there was no `epsg` file there. I then figured out I had to install
some extras from yum:

``` bash
yum install proj49-epsg proj49-nad
```

And then looked again. The path was slightly different. Ran again.

``` r
# install sf (this will fail if GDAL_DATA is not set for gdal)
args2 <- c("--with-gdal-config=/usr/bin/gdal-config", 
           "--with-geos-config=/usr/geos37/bin/geos-config", 
           "--with-proj-share=/usr/proj49/share/proj")
install.packages("sf", configure.args = args2)
```

This works now. Went on to install `fasterize` and `dbplyr` without
complaint. `lwgeom` needs a bit extra:

``` r
# install sf (this will fail if GDAL_DATA is not set for gdal)
args2 <- c("--with-geos-config=/usr/geos37/bin/geos-config", 
           "--with-proj-share=/usr/proj49/share/proj")
install.packages("lwgeom", configure.args = args2)
```

Now back to `RpostgreSQL`. The problem of course is that `pgsql` is in a
non-standard location, and was failing to locate a `libpq-fe`, which is
part of the `postgres` install. So I tried configure.args to point it to
the right place. It didn’t work.

``` r
args2 <- "--with-pg-include=/usr/pgsql-9.4/include"
install.packages("RPostgreSQL", configure.args = args2)
```

The solution I found was to use symlinks, from
[here](https://stackoverflow.com/questions/23821506/rpostgresql-installation-error-rpostgresql-so-undefined-symbol-pqpass).

``` bash
ln -s /usr/pgsql-9.4/lib /usr/lib/pgsql
ln -s /usr/pgsql-9.4/include /usr/include/pgsql
```

After that, it installed fine just as `install.packages("RPostgreSQL")`

So I think that about does it for R. We can check to see whether
everything we wanted is in the installed list:

``` r
pkgs <- c("sf", "lwgeom", "RPostgreSQL", "devtools",  "raster", "rgdal",
          "dplyr", "dbplyr", "aws.s3", "data.table", "DBI", "units", 
          "fasterize")
pkgs %in% unname(installed.packages()[, 1])
```

### python

First have to install `pip`, outside of `root` for some reason.

``` bash
sudo yum install python2-pip
```

And then:

``` bash
pip2 install crontab
pip2 WebOb  # version 1.8.5
```

### Bring in `labeller` code base

`ssh` into mapper and sandbox in turn, and run:

``` bash
git clone https://<user>@github.com/agroimpacts/labeller.git
```

Replacing <user> with my GitHub user name, when `labeller` repo was
private. If it is open (which it will be soon), drop the “user@” parts
from the above.

## Configure database

After having done these installs, the next step is to set up the
databases, which includes adding the `postgis` extensions.

### Setting up the database

Mapper is set up to have a sandbox database, but we are shifting to a
single database only (`Africa`). The code will continue to support the
existence and use of an `AfricaSandbox`, thus there are many vestigial
references to that database.

#### Set up pg\_hba.conf

Step 1: Using template from `/home/mapper/labeller/pgsql`, as root:

  - Copy that template to `/var/lib/pgsql/9.4/data`, make a backup of
    the existing one
  - Change permissions to 600
  - Change ownership to postgres:postgres

<!-- end list -->

``` bash
cp /var/lib/pgsql/9.4/data/pg_hba.conf /var/lib/pgsql/9.4/data/pg_hba.confbak
cp /home/mapper/labeller/pgsql/pg_hba.conf /var/lib/pgsql/9.4/data/pg_hba.conf
chmod 600 /var/lib/pgsql/9.4/data/pg_hba.conf
chown postgres:postgres /var/lib/pgsql/9.4/data/pg_hba.conf
```

Then use `vim` to edit `/var/lib/pgsql/9.4/data/pg_hba.conf`: - Comment
all ‘all postgres md5’ lines - Uncomment all ‘all all trust’ lines

Step 2: Next, as root, run:

``` bash
#/usr/pgsql-9.4/bin/postgresql94-setup initdb  # this is probably done already
systemctl start postgresql-9.4.service
systemctl enable postgresql-9.4.service
```

Step 3: Create passwords for the databases. This also requires setting
set up a configuration file. In `/home/mapper/labeller/common` there is
a `config_template.yaml` we will use:

``` bash
su - mapper  # to change from root to mapper
cd /home/mapper/labeller/common/
cp config_template.yaml config.yaml
vim config.yaml
```

You then edit the empty top lines to look like this, replacing the
passwords with something nice and secure:

``` vim
mapper:
    DEBUG:
    SECRET_KEY:
    # Key connection parameters.
    db_production_name: Africa
    db_sandbox_name: AfricaSandbox
    db_username: postgis
    db_password: <a clever password overwrites all of this>
    dbpg_password: <another clever password overwrites all of this>
```

`config.yaml` is not tracked by `git`, so use this only locally (or a
copy kept in your S3 bucket) to store key credentials. This file is used
by many routines in `labeller`, so it will be filled in as `labeller` is
built up.

Next, we call our python script which sets up to further non-tracked
text files that will be used for various `postgres` transactions. The
script is `create_passfiles.py`, which reads `config.yaml`

``` bash
cd /home/mapper/labeller/pgsql
python create_passfiles.py
```

Which outputs:

    Created /home/mapper/labeller/pgsql/pgpassfile_mapper
    Created /home/mapper/labeller/pgsql/pgpassfile_sandbox
    Created /home/mapper/labeller/pgsql/role_create_su.sql

Step 5: Change the PostgreSQL postgres password, and create the postgis
role as superuser. The `role_create_su.sql` is used here:

``` bash
exit # to get back to root
cd /home/mapper/labeller/pgsql
chmod 600 role_create_su.sql
psql -U postgres
\i role_create_su.sql
\q
```

Step 6: Some more changes after that to `pg_hba.conf`, made as root:

``` bash
vim /var/lib/pgsql/9.4/data/pg_hba.conf
```

  - Uncomment all ‘all postgres md5’ lines
  - Comment all ‘all all trust’ lines
  - Uncomment all ‘postgres postgis md5’ lines. On this last point, note
    the admonishment in the comment above it:

<!-- end list -->

``` vim
# You may want to comment out the next line in production for additional security.
# It must be UN-commented to run restoreRenamedDbFromBackup.sh
```

Step 7: Changes after that to `postgresql.conf`, made as root:

``` bash
vim /var/lib/pgsql/9.4/data/postgresql.conf
```

  - Uncomment the ‘listen\_addresses’ line, and change ‘localhost’ to
    ’\*’.

Step 8: As root, run `systemctl restart postgresql-9.4.service` for
changes to take effect.

#### Create database

##### Create from scratch

The following sets up the database, and includes a password prompt. Note
we are creating thes under user postgis to make sure all postgis
permissions attach to it. This is more time-consuming, but shown here
for completeness.

``` bash
cd /home/ec2-user # to avoid permission denial for /home/mapper/...
su postgres
createdb -U postgis Africa  # create with user postgis
```

Then create the postgis extensions:

``` bash
psql Africa postgis
```

This gives a password prompt, and then we are in `postgres`, and want to
enter these commands:

``` postgres
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
CREATE EXTENSION postgis_sfcgal;
SELECT postgis_full_version();
```

This is from [here](https://postgis.net/install/) and
[here](http://www.postgresonline.com/journal/archives/362-An-almost-idiots-guide-to-install-PostgreSQL-9.5,-PostGIS-2.2-and-pgRouting-2.1.0-with-Yum.html)

The last line gives this:

``` postgres
                                                                              postgis_full_version                                                                                    
----------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
 POSTGIS="2.4.3 r16312" PGSQL="94" GEOS="3.7.1-CAPI-1.11.1 27a5e771" SFCGAL="1.3.1" PROJ="Rel.
 4.9.3, 15 August 2016" GDAL="GDAL 2.2.3, released 2017/11/20" LIBXML="2.9.1" TOPOLOGY RASTER
(1 row)
```

Repeat the same to make the `AfricaSandbox` database, just in case its
absence causes problems.

##### Using existing scripts and database

This is much faster, as it puts in place everything `labeller` needs in
it’s database, but relies on an existing backed-up database that lives
in s3.

It first requires having a pre-existing database to restore. To
facilitate that, there is a canonical `labeller` database available on
an S3 bucket (**make this publicly available and edit**), which is used
to create the database.

At the point, to use those scripts, we will need to install the `aws
cli`, which we do following and adapting AWS’s
[instructions](https://docs.aws.amazon.com/cli/latest/userguide/install-linux.html)
for this purpose, as user mapper (and sandbox, if needed):

###### aws cli

``` bash
pip install awscli --upgrade --user
aws configure
```

That prompts one to enter the AWS access key id, the secret key, the
default region (us-east-1), and output format (text). We add for a
specific user in this case, but ideally the build should really on an
IAM role for the instance (**investigate changing this**).

A quick check will tell us if it is connecting properly:

``` bash
aws s3 ls s3://activemapper/
```

It should return a list of bucket contents. If the command isn’t found,
you might have to add the path to where the install was made to your
.bash\_profile. But this install did not require it.

###### phpPgAdmin

Next, before adding the databases, we’ll install phpPgAdmin, which is
useful for looking at the databases.

Following instructions
[here](https://dinfratechsource.com/2018/11/10/installing-postgresql-9-4-phppgadmin-in-centos-7/)
mostly for just the install part from `yum` for phpPgAdmin under heading
“Manage PostgreSQL with phpPgAdmin”. From root:

``` bash
yum install phpPgAdmin httpd
```

That installs the necessary packages, and now some configurations need
to be made. We want to be fairly restrictive here on who can log into
the database, so we are going to use our own `phpPgAdmin.conf` locked
down to just the IP addresses we want to allow access to. To that end we
are going to use the `labeller/pgsql/phpPgAdmin_template.conf`. First,
copy this file to an untracked version `phpPgAdmin.conf`

``` bash
cd /home/mapper/labeller/pgsql/phpPgAdmin_template.conf /home/mapper/labeller/pgsql/phpPgAdmin.conf
```

Then open up `phpPgAdmin.conf` and replace these lines:

    #       A description of your first allowed location
            Allow from XXX.YYY.J.Q/16
    #       A description of another allowed location
            Allow from XXX.YY.JJJ.QQ

With the IP addresses (including any ranges) and associated helpful
descriptions of where those are (e.g. My office), for as many entries as
you need. Then use that file to replace
`/etc/httpd/conf.d/phpPgAdmin.conf`, first backing up the former

``` bash
cp /etc/httpd/conf.d/phpPgAdmin.conf /etc/httpd/conf.d/phpPgAdmin.confbak
cp /home/mapper/labeller/pgsql/phpPgAdmin.conf /etc/httpd/conf.d/phpPgAdmin.conf
ls -l /etc/httpd/conf.d/phpPgAdmin.conf
```

The resulting permissions should look like this:

``` bash
-rw-r--r--. 1 root root  877 Aug 18 12:42 phpPgAdmin.conf
```

Then, in `/etc/phpPgAdmin/config.inc.php`, set line 31 to look like
this:

``` bash
$conf['servers'][0]['defaultdb'] = 'Africa';  # solution found by Dennis
```

After this:

``` bash
systemctl start httpd
systemctl enable httpd
```

And then after that:

``` bash
systemctl restart postgresql-9.4
systemctl restart httpd
```

But so far haven’t been able to log in using instance’s IP, either using
http or https.

###### Restore database

We use a simple shell script to restore our database from the canonical
database, we get a fully built, fresh Africa database. This is run under
user `mapper`

``` bash
cd /home/mapper/labeller/pgsql/
./restore_db_from_s3.sh
```

This prompts for a number of inputs, and then runs for quite a while,
but installs everything. After doing that edit
`/var/lib/pgsql/9.4/data/pg_hba.conf`, by commenting all ‘postgres
postgis md5’ lines, and adding support for the new database name (if not
already in pg\_hba.conf))

###### Set up \~/.pgpass

Last thing to do is set up a \~/.pgpass file for mapper, using the files
created with `create_passfiles.py`

``` bash
chmod 600 /home/mapper/labeller/pgsql/pgpassfile_mapper  # assuming as root
su - mapper
cp /home/mapper/labeller/pgsql/pgpassfile_mapper ~/.pgpass
```

That allows password-less execution of db scripts

# Set up daily DB backups

The only remaining thing to do is a daily backup using
`crontabSetup.root`. We’ll hold off on that for now.

### Port configuration

## Setting up `labeller`’s code base

First, although not necessarily needed as first step, build the
`rmapaccuracy` package that is within `labeller`, which provides the
accuracy assessment and consensus labelling code.

From root:

``` bash
/home/mapper/labeller/spatial/R/build_rmapaccuracy.sh
```

That runs a `devtools` based build that doesn’t update R package
dependencies, to avoid breakages from new packages.

### Getting the webapp running

From here, to get Apache running for basic retrievals, a number of
different steps were needed.

#### permissions

Then allow the apache user to have mapper as a secondary group. In
`/etc/group`, append ‘apache’ to ‘mapper’ line as shown below:

``` bash
mapper:x:1001:apache
```

Change permissions: `/home/mapper` should have 750 permissions and
mapper:mapper ownership. `/home/mapper/labeller` directory should have
770 permissions and mapper:mapper ownership (as should all directories
below labeller. And all files below labeller should have 660 permissions
and mapper:mapper ownership.)

#### yum installs

Some additional installs are required:

``` bash
yum install mod_wsgi
yum install mod_ssl
yum install mailx
setsebool httpd_read_user_content on
```

`postfix` was previously needed by was ok as is. NOTE: Use the `mail`
command to test that an email can be successfully sent to a gmail and
other accounts.

#### selinux changes

The following had to be done:

``` bash
setsebool -P httpd_read_user_content 1
setsebool -P httpd_can_network_connect_db 1
setsebool -P httpd_can_network_connect 1
```

Then copy all the *.te and* .pp files from `/home/mapper/labeller/etc/`
to `/var/log/audit` directory on mapper0:

``` bash
cp /home/mapper/labeller/etc/*.pp /var/log/audit
cp /home/mapper/labeller/etc/*.te /var/log/audit
```

And execute:

``` bash
cd /var/log/audit # as root
pp=`ls *.pp`
for item in ${pp[*]}; do semodule -i $item; done
```

If you suspect an selinux denial, then:

1.  Run the suspected code while running `tail /var/log/audit/audit.log`

2.  Copy the audit.log lines to a new file (e.g., foobar.log)

3.  Run:
    
    ``` bash
    audit2allow –I foobar.log –M foobar
    cat foobar.te
    ```

4.  If it suggests setting a Boolean:
    
    ``` bash
    setsebool –P <suggested_boolean> 1
    ```
    
    if not:
    
    ``` bash
    semodule –I foobar.pp
    ```
    
    #### Flask

To install Flask modules we need:

``` bash
pip install Flask-User==0.6.19  
```

The first line is to prevent Flask 1.0 from being installed, which is
not backward compatible with the version we developed with.

See these files in /usr/lib/python2.7/site-packages:

  - flask\_user.orig/db\_adapters.py and flask\_user/db\_adapters.py
    differ
  - flask\_user.orig/forms.py and flask\_user/forms.py differ
  - flask\_user.orig/**init**.py and flask\_user/**init**.py differ
  - flask\_user.orig/settings.py and flask\_user/settings.py differ
  - flask\_user.orig/views.py and flask\_user/views.py differ
  - flask\_user.orig/templates/flask\_user/invite.html and
    flask\_user/templates/flask\_user/invite.html differ
  - flask\_user.orig/templates/flask\_user/register.html and
    flask\_user/templates/flask\_user/register.html differ

These are committed in `labeller/etc`, so on install, as root:

``` bash
FLASKDIR=/usr/lib/python2.7/site-packages/flask_user
REPODIR=/home/mapper/labeller/etc/flask_user
cp $FLASKDIR /usr/lib/python2.7/site-packages/flask_user.orig

files=(db_adapters, forms, __init__, settings, views)
for item in ${files[*]}; do cp $REPODIR/$item.py $FLASKDIR; done
cp $REPODIR/invite.html $FLASKDIR/templates/flask_user/
cp $REPODIR/register.html $FLASKDIR/templates/flask_user/
```

Then some more installs

``` bash
pip install Flask-Migrate
pip install Flask-Script
pip install psycopg2-binary
pip install PyGithub==1.35 
```

NOTE: The versioned PyGithub avoids requiring a version of `requests`
that is incompatible with `certbot`

#### Set up an elastic IP

This can be scripted as follows:

``` bash
AID=`aws ec2 allocate-address --query 'PublicIp'`
INAME=labeller
IID=`aws ec2 describe-instances --filters 'Name=tag:Name,Values='"$INAME"'' \
--output text --query 'Reservations[*].Instances[*].InstanceId'`
echo $IID
NWID=`aws ec2 describe-instances --instance-ids $IID --filters --output text --query "Reservations[].Instances[].NetworkInterfaces[].NetworkInterfaceId"`
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
ZONE=crowdmapper.org
HOSTEDZONE=`aws route53 list-hosted-zones-by-name --dns-name $ZONE --output text --query 'HostedZones[*].Id'`

# add record to hosted zone
ZONEPREFIX=labeller  # choose name here
aws route53 change-resource-record-sets --hosted-zone-id $HOSTEDZONE --change-batch '{"Changes": [{"Action": "CREATE", "ResourceRecordSet": {"Name": "'$ZONEPREFIX'.'$ZONE'", "Type": "A", "TTL": 300, "ResourceRecords": [{ "Value": "'$AID'"}]}}]}'

# Start and stop the instance
aws ec2 stop-instances --instance-ids $IID
aws ec2 start-instances --instance-ids $IID
```

Also tried manually adding an SPF record (through a TXT record) to
prevent gmail from routing the message to spam, but it didn’t work.

##### certbot

To create a cert for a new server, run:

``` bash
~/labeller/common/certbot.sh
```

And specify the hostname of the required cert on the command line.

`certbot` needs a directory called `~/labeler/.well-known` to exist and
be world readable by `apache`. The latter is already done, and I have
manually added the hidden directory to both mapper0 and labeler. But it
is not committed to the github repo and needs to be, so that it will
automatically be recreated when building an instance from scratch. c. To
install certbot, follow steps 1-4 in these instructions:
<https://www.thegeekdiary.com/centos-rhel-7-how-to-change-set-hostname>
d. Test by typing ‘certbot’ at the command line. If it fails with a
traceback, install the ‘requests’ module: pip install requests==2.6.0

##### Continue to populate config.yaml

Although started earlier, /home/mapper/labeller/common/config.yaml will
needed more required values at this stage. NOTE: YAMLLoadWarning:
calling yaml.load() without Loader=… is deprecated, as the default
Loader is unsafe. Please read <https://msg.pyyaml.org/load> for full
details.

``` python
params = yaml.load(yaml_file)
```
