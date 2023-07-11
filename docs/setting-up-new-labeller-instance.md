# Setting up a new labeller instance
This assumes that an up to date AMI of `labeller` exists, containing the latest code and configurations. If such an AMI does not exist, then the first step is to create it from the most up to date instance. 

## Create AMI, if needed

First stop the instance you want to image:
```bash
./common/tools/stop_instance.sh
```

You will be prompted for the name of the instance to stop--note this script only works for named instances. 

The create the AMI:

```bash
./common/tools/create_ami.sh <instance_name> <ami_name> 
```

Where the first argument is the name of the instance you just stopped and want to image (e.g. `labeller`), and the second is the name you want to give to the AMI (e.g. also `labeller_20191609`, for the image of a given date--just make sure you don't use the same name as an AMI that already exists.

## Create new instance
Once the AMI has been created, you can run the following script to create a new instance from that AMI (or one that already exists):

```bash
./common/tools/create_instance.sh <ami_id> <instance_type> <security_group> \ <new_instance_name>
```

You get the first argument (the AMI id) from the terminal output from the `create_ami.sh`, otherwise you need to find it in AWS EC2 console. For the second argument, we generally use "t2.large", and then a properly configured security group (e.g. "labeller-security") is important. Finally, we want to choose a suitable name for the instance (e.g. "labeller1"). 

This will create a new instance that will take a few minutes to spin up fully. 

## Make the new instance web accessible

This entails creating new web addresses for the mapper and sandbox versions of the new instance, and then assigning to the new instance, and making the necessary changes within the instance itself. 

### Create static IP for new instance

The script below will run through the process of: 

1. Creating a new elastic IP address
2. Get the network interface ID
3. Assign a private IP to the network interface
4. Associating the elastic IP with the instance
5. Adding that to a record set within the hosted zone on Route 53

At the end this will provide a static IP address that will remain constant through instance restarts:

```bash
./common/tools/create_elasticip.sh <instance_name> <zone_name>
```

Use the instance name you just created, and then provide a zone name (i.e. domain name) that you want to associate with the elastic IP address. For instance, if we use "labeller1" and "crowdmapper.org", our resulting web address will be `labeller1.crowdmapper.org`. 

That script stops the instance, so you just need to restart it:

```bash
# Start and stop the instance
./common/tools/start_instance.sh
```

And give it the instance name when prompted

## Configurations on the new instance

`ssh` into the instance as the root user, which assumes that your AMI already has your `ssh` public keys in it.  (Note that there is likely a way to do all of this remotely through `ssh`, but will require changing some scripts to do so, so keeping it manual for now).

#### git
As user mapper from do `git pull` to get the latest version from the repo on the correct branch, just as a precaution 

#### Rebuild `rmapaccuracy` 
```bash
/home/mapper/labeller/spatial/R/build_rmapaccuracy.sh
```

#### Create new hostname and certificate

We'll create a new hostname for the machine and certificate that allows https authentication using this script, which must be run from root:

```bash
/home/mapper/labeller/common/certbot.sh <new hostname> <old hostname>
service httpd restart
```

Where <new hostname> is the one for the instance you just created (e.g. `labeller1.crowdmapper.org`) and <old hostname> is most likely the name of the hostname for the instance that you used to create the AMI (.e.g `labeller.crowdmapper.org`). If you are not sure, you can always, as root, look it up by running:

```bash
ls /etc/letsencrypt/archive/
```

Which will show you the old hostname. 

Once you have done that, run `hostname` to check that the host name was changed, and then you should be able to access the webapp and phpPgAdmin via https (you might have to refresh your browser). 


#### Clear out logs and database
```bash
rm -f /home/mapper/labeller/log/*
rm -rf /home/mapper/labeller/maps/*
rm -rf /home/mapper/labeller/spatial/R/Error_records/*
```

#### Update database and file system

If your AMI has basically a clean database, there is not much you need to do, although clearing the database is a good precaution:

```bash
./pgsql/clear_db.sh
```

But perhaps you want to bring in some changes from other instances or database copies. There are several ways to do this:

##### Restore from a database backup

The most straightforward way to update the database of a new instance is to restore a backup of the most up to date database from another instance from s3. To do this, run, when logged into the instance as user `mapper`:

```bash 
./pqsgl/restore_db_from_s3.sh
```

Which you will point to a back up under a relevant folder on S3. Probably best to clear out the database itself to make it fresh:

```bash
./pgsql/clear_db.sh
```

This will keep all user data, so there might be a conflict that occurs with generating consensus maps if you don't revoke the qualifications of those workers before running the new instance in production. Specifically, the workers will already be approved (because they likely have a complete Q history in `worker_data`), which means there assignments will be approved and consensus maps can be created before any score history is available in `accuracy_data`. This will cause the consensus map to fail for early HITs. To avoid this, it is best to revoke qualifications, and then immediately restore them:

```bash
./pqsql/reset_worker_qualifications.sh
```

### Restore specific tables
Alternatively, you might have a good database, but perhaps just want to update a a few tables. Go to the instance that has the most complete tables that you need for the new instance. For example, `scenes_data`, `kml_data`, and `configuration`. Use:

```bash
./pgsql/backup_tables_to_s3.sh 
```

From the instance that has the versions of the table you want, which will back them up to S3. Then log into the new instance's sandbox, and from there run:

```bash
./pgsql/restore_tables_from_s3.sh 
```

***[Below here still needs updating]***

### config files
There are two ways to test cvml and mapper interaction:
1. by starting terraform directly with terraform apply, therefore using the config file specified in the terraform/emr.tf
2. by running the fire_up_mapper.py script to generate a new config file with the command line arguments supplied to `fire_up_labeller.py` see [running labeller in production](running-labeller-in-production.md).

When setting up a new mapper instance there should probably (?) be a new config file on s3 for that mapper instance that specifies the different aoi name and file paths on s3 that the instance will use. Unless we just choose to always use `fire_up_labeller.py`. A config file, whether manually created or genrated from `fire_up_labller.py`, is created from the `config_template.yaml` and new params or changes to the config structure must be included in config_template for `fire_up_labeller.py` to work. 

Some gotchas/guidelines for setting up the config and final checkups before starting a run:
* Make sure config is set up to the have the db_host pointing to the private DNS address of the instance. Otherwise the DB insert step in cvml won't work, because both cvml and mapper read the same config file on s3
* make sure that the correct incoming_names.csv and f_pool.csv are specified
* check to make sure that mapper is on the correct branch
* check the emr.tf file to make sure mapper is pulling the correct cvml branch

### daemons
You might well have to update the permissions to 600 on  /home/mapper/labeller/pgsql/pgpassfile_* ., otherwise daily backups might not run. To do this, please refer to the [pgsql/README](../pgsql/README.md) file (step 10) 

