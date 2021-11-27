# Migrating `mapper` from Development into Production

These notes (compiled by Dennis McRitchie) describe the steps for migrating databases from AfricaSandbox (development environment) to Africa (production environment)

## DB Migration Notes:
The `pgsql/migrate.sh` script performs the database migration and can only be run from user mapper.

In part, it relies on the output of the `generateUpdateConfigurationSandbox.sh` script, and also calls the `clear_db.sh` script internally.

The steps to running a DB migration from AfricaSandbox to Africa are as follows:

1. First, make sure you are logged in as user mapper:

    ```bash
    ssh mapper@<instance-name>.crowdmapper.org
    cd mapper
    ```

2. Turn off crontab and daemons

    ```bash
    crontab -r
    common/daemonKiller.sh
    ```

    Check and see if crontab is off and no daemons are left running. 

    ```
    crontab -l 
    ps -ef | grep mapper
    ``` 
    Note that you do not need to turn off daemons running under sandbox.

3. In order to handle the need to change some of the values of configuration table parameters for production, as well as handling the addition or removal of parameters since the last migration, as user mapper, run `generateUpdateConfigurationSandbox.sh`   

    This will create a file called updateConfigurationSandbox.sql containing all the parameters, values and comments contained in AfricaSandbox's configuration table. 
    
    If a file called `updateConfiguration.sql` already exists, rename it in order to save its contents. 
    
    Then copy updateConfigurationSandbox.sql to updateConfiguration.sql, and make any edits needed to set the parameters values needed for production. You can 'diff' the saved version of `updateConfiguration.sql` in order to see what parameters were changed for the last migration.

4. Run `migrate.sh`. This script will prompt you for the postgres and postgis user passwords, perform backups of Africa and AfricaSandbox, and then perform a restore of the AfricaSandbox backup into a new instance of the Africa DB. It then makes the following changes to the newly restored Africa tables:

    
      a. It internally runs clear_db.sh which makes the following changes:
      
          - empties user_maps
          
          - empties accuracy_data
          
          - empties assignment_history
          
          - empties assignment_data
          
          - empties qual_user_maps
          
          - empties qual_accuracy_data
          
          - empties qual_assignment_data
          
          - empties hit_data
          
          - empties kml_data
          
          - resets kml_data's gid sequence to 1
          
          - replenishes kml_data with the rows from kml_data_static
          
          - sets system_data param CurQaqcGid to 0
          
          - sets system_data param firstAvailLine to 1
          
   
      NOTE: `clear_db.sh` can be run from the command line from either the mapper or sandbox user to make the above changes to the associated DB.

      b. Populates the following tables with the contents from the Africa DB backup (NOTE: this means that these tables will NOT have changed as a results of the migration):
      
          - worker_data
          
          - user_invites
          
          - users_roles
          
          - users

          - roles
          
          - incoming_names
          
          - iteration_metrics
          
          - sets the system_data param IterationCounter to the highest iteration number in iteration_metrics
          
          - Clean and reset master_grid: avail='Q' for Qs in kml_data_static, avail='I' for Is in kml_data_static, avail='T' for others
          
          - updates the configuration table with the params, values, and comments in `updateConfiguration.sql`
          
      c. ALL remaining tables not listed above are copied intact from AfricaSandbox to the Africa database.
