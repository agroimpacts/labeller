# Running labeller in production

Having set up and configured a new instance, you are now ready to run `labeller` in production. The following describes the steps for starting up the full active learning loop, in which `labeller` triggers `learner` in on EMR cluster each time the workers on `labeller` complete a set of assignments.  

## Steps
### Update your database

**Note**: this step should already have been done at the stage of [setting up a new instance](setting-up-new-labeller-instance.md), but is repeated here in case instance set up was done some time ago.

It might happen that one instance has a more up to date core database or table than the one you have just made, because, for example, you created the instance from an out of date AMI.  The best examples for tables that could be outdated are: *kml_data_static*, *qaqcfields*, and *scenes_data*, but maybe you want to keep user data from a different instance also, and see need all those affiliated tables. 

These can be selectively copied from the instance where they are most up to date to S3 using:

```bash
pgsql/backup_tables_to_s3.sh 
```

And then updated on the instance being migrated using:

```bash
pgsql/restore_tables_from_s3.sh 
```

### Log-in

From your local machine
```
ssh into mapper@<instance-name>.crowdmapper.org
```

### Shut down `mapper`'s daemons

As user `mapper`, shut down crontab and kill any running daemons on `labeller`. 

```bash
crontab -r
common/daemonKiller.sh
```

### Configure `labeller`

Following migration, `labeller` has to be configured to run `learner`. To do this, we will run `fire_up_labeller.py`, which takes a number of arguments and automatically sets up configuration files. The argument can be understood by running:

```bash
python common/fire_up_labeller.py --help
```

Which returns:

```bash
Usage: fire_up_labeller.py [OPTIONS]

Options:
  --initial INTEGER               The labeller mode: 1 initial; 2 single; 3
                                  regular.
  --ec2_instance TEXT             The name of the labeller instance.
  --run_id INTEGER                The run id of the iteration.
  --aoi_index INTEGER             The index of the aoi in geojson the
                                  iteration will run on.
  --aoi_name TEXT                 The general name of the aoi.
  --aoi_s3_object TEXT            The name of AOI geojson in
                                  S3/activemapper/grid.
  --incoming_names_static_path TEXT
                                  The S3 path of static incoming names.
  --github_branch TEXT            The branch name of learner to pull.
  --github_repo TEXT              The repo to steer issues to.
  --worker_type TEXT              The worker type of emr worker.
  --bid_price FLOAT               The bid price of emr worker.
  --worker_count INTEGER          The number of emr worker.
  --bucket TEXT                   The name for S3 bucket.
  --number_outgoing_names INTEGER
                                  The number of outgoing names.
  --num_possibilities INTEGER     The number of possibility maps to save out
                                  each iteration.
  --security_group_id TEXT        The security group id of learner.
  --secret_key TEXT               The secret key for labeller.
  --db_user TEXT                  The name of database user.
  --db_pwd TEXT                   The password of database.
  --github_token TEXT             The github token of maphelp.
  --api_key TEXT                  The api key for downloading planet.
  --aws_access TEXT               The aws access key.
  --aws_secret TEXT               The aws secret key.
  --aws_region TEXT               The aws region.
  --slack_url TEXT                The url of slack APP.
  --worker_vcpu INTEGER           The number of cup for workers.
  --worker_mem_yarn INTEGER       The size of memeory yarn for workers.
  --executor_cores INTEGER        The number of executor cores for workers.
  --image_catalog_predict         The catalog of images to apply the model.
  --help                          Show this message and exit.
```

A fully formed command will thus look something like this (note that all user names, keys and passwords are stripped out here and denoted with <user>, <key> and <pw>):
**NOTE:** make sure you set the 'aoi_s3_object' and 'master_grid_s3_object' in config_template.yaml correctly first since these two are needed in the script.

```bash
python common/fire_up_labeller.py --initial 1 --ec2_instance "labeller3" --run_id 0 --aoi_index 3 --aoi_name "ghana" --aoi_s3_object "image_target_aois.geojson" --incoming_names_static_path "incoming_names_static_cluster1.csv" --github_branch "master" --github_repo "agroimpacts/issues" --worker_type "m4.xlarge" --bid_price 0.086 --worker_count 130 --bucket "activemapper" --number_outgoing_names 100 --num_possibilities 30 --security_group_id "sg-0a8bbc91697d6a76b" --secret_key <key>  --db_user "postgis" --db_pwd <pwd> --github_token <token> --aws_access <key> --aws_secret <secret> --aws_region "us-east-1" --slack_url <url> --worker_vcpu 16 --worker_mem_yarn 24 --executor_cores 5 --image_catalog_predict "planet_catalog_ghana_1.csv"
```

This would set up the `labeller` instance. 

From there, there are two separate ways to start the work: 

1. Initial drawing; 
2. Single independent labelling;, almost the same as initial drawing.
3. Regular production.

Before start, I hightly recommend to read the script first to make sure everythin is what you want. Because in the past few months, so many last-minute casual changes to the system rules which is super dangerous. 

### Initial drawing

If this is the initial drawing, then you run

1. `fire_up_labeller.py` first by using `--initial 1`, the other parameters refer to the above.

2. `pgsql/clear_db.sh` to clean the database.

3. `spatial/R/update_db.R` to update the database for initial drawing.

_Note:_ Single mode is the same, but using `--initial 2`.

### Regular production

1. `fire_up_labeller.py` first by using `--initial 3`.

2. `pgsql/clear_db.sh` to clean the database.

3. `spatial/R/update_db.R` to update the database for initial drawing.

4. Create target geography

The next step is to specify the geography that the instance will focus on for this run. We first create a geojson that has a number of rectangular polygons in it. These define the locations of all possible mapping geographies that `learner` could operate on. We will select one of those polygons as the focus. At this step, it is also to create an initial random draw of training sites from that F pool. These are the sites that must be mapped before the first machine learning process is run. 

To do, we run 
```bash
Rscript spatial/R/create_f_pool.R 1
```

**NOTE:** before this step, double-check the DB to make sure master_grid and kml_data table matches with kml_data_static table. And in this step, we subset the full planet catalog stored in S3 and insert them into scenes_data table in DB. So the scenes_data table should be blank in the beginning.

  *Optional*: Draw initial set of training, holdout, and validation sites

This script is used to put the names in incoming_names into kml_data table, you could run it manually for testing. 

```bash
python common/initial_f_sites.py
```

5. Restart daemons
Finally, when all that is completed, restart the daemons. To do this, use the utility `crontab_runner.py`:

```bash
cd /home/mapper/labeller/common
python crontab_runner.py --help
```

Which returns:
```bash
Usage: crontab_runner.py [OPTIONS]

Options:
  --command TEXT    Defaults to crontab, but echo can be run to test
  --cleanup TEXT    Defaults to T, but can be F
  --hits TEXT       Defaults to F for basic maintenance. T for production
  --consensus TEXT  Enter T to generate consensus labels or F if not
  --notify TEXT     Enter T to have slack notifier run, F if not
  --nsites TEXT     Enter T if you want N sites served up, F if not
  --help            Show this message and exit.
```

This means you can run varying combinations of daemons, depending on what kind of run you want to do. E.g. 

If you want just F and Q sites, and no N, run (**note: this is currently the preferred daemon configuration**):
```bash
crontab crontabSetup_no_n.mapper 
```
Make sure the email address is updated to the one where you want notifications to go in configuration table for the instance (currently the notifier is typically setup to send to a slack channel).

If you want to do the same (just F and Q sites, and no N) but no notifier, run:
```bash
crontab crontabSetup_no_n.mapper 
```

Finally, a standalone version that only create F sites and won't fire cvml (provided you have tuned configuration parameters correctly) is 

```bash
crontab crontabSetup_standalone_f.mapper 
```

This keeps `generate_consensus_daemon` turned off. 

  *Optional*. start the worker notification

Run the script to turn on the worker notification:
```bash
cd labeller/log
nohup python -u ~/labeller/common/worker_notification_daemon.py &
```

## Ready for mapping!

**NOTE:** don't forget to restart the apache by `sudo service httpd restart` if you change anything related to the web.

Workers then have to log in to the mapper side of the instance to start the ball rolling. 

## How to reset the instance for another run

Let's say you have finished run 0, and want to re-initialize mapper for another run.  Go through these steps:

1. Shutdown daemons
```bash
crontab -r
common/daemonKiller.sh
```

2. Backup key tables to s3
```bash
cd /home/mapper/labeller/pgsql
./backup_production_tables_to_s3.sh
```

3. Clear out those tables on production database
```bash
./clear_db.sh
```

4. Run `fire_up_labeller.py`
```python
python common/fire_up_labeller.py --ec2_instance "ghana0" --run_id 1 --aoi_id "GH0049089_GH0111165" --github_branch "master" --worker_type "m4.xlarge" --bid_price 0.086 --worker_count 80 --bucket "activemapper" --number_outgoing_names 20 --security_group_id "sg-ac924ee6" --secret_key "<key>"  --db_user "<user>" --db_pwd "<pw>" --github_token "<key>" --api_key "<key>" --aws_access "<key>" --aws_secret "<key>" --aws_region "us-east-1"
```

5. Run `initial_f_sites.py` again
```python
python common/initial_f_sites.py
```

6. Restart daemons
```bash
crontab crontabSetup_no_n_notifier.mapper 
```

