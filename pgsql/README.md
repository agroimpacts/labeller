# pgsql-related

NOTE: use scripts referred to here only to:

1) perform an initial installation of the postgresql server, and 

2) an initial create or restoration of databases (e.g., Africa, AfricaSandbox), and

3) to setup initial database backups.

NOTE: all steps must be followed in order from the beginning.

NOTE: If updating postgis to a later version, modify the steps below to
follow the procedure described at this link:
http://postgis.net/docs/postgis_installation.html#hard_upgrade

## PostgreSQL configuration

1) As root, copy the local pg_hba.conf to /var/lib/pgsql/9.4/data:
   - change ownership to postgres:postgres
   - change permissions to 600.
   - comment all 'all postgres md5' lines
   - uncomment all 'all all trust' lines
2) As root, run:
a) /usr/pgsql-9.4/bin/postgresql94-setup initdb
b) systemctl start postgresql-9.4.service
c) systemctl enable postgresql-9.4.service
3) Change the PostgreSQL postgres password, and create the postgis role as superuser:
    psql -U postgres
    \i role_create_su.sql
4) As root, edit /var/lib/pgsql/9.4/data/pg_hba.conf:
   - uncomment all 'all postgres md5' lines
   - comment all 'all all trust' lines
   - uncomment all 'postgres postgis md5' lines
5) Edit /var/lib/pgsql/9.4/data/postgresql.conf, uncomment the 'listen_addresses'
   line, and change 'localhost' to '*'.
6) As root, run 'systemctl restart postgresql-9.4.service'

## Create/restore database

7) As superuser postgis, create the desired (e.g., Africa or AfricaSandbox) database 
   and schema by running the restore script:
   (NOTE: having the script log into Postgresql as superuser postgis to do this 
    ensures that all postgis extension objects are owned by postgis.)
   /home/mapper/labeller/pgsql/restoreRenamedDbFromBackup.sh
     or
   /home/sandbox/labeller/pgsql/restoreRenamedDbFromBackup.sh
   NOTE: This script will restore postgis to be a regular DB user (not a superuser).
8) As root, edit /var/lib/pgsql/9.4/data/pg_hba.conf:
   - comment all 'postgres postgis md5' lines
   - add support for the new database name (if not already in pg_hba.conf))
9) Copy /var/lib/pgsql/8.4/data/pg_hba.conf to .../pgsql/pg_hba.conf (if changed),
   and change its permissions and ownership to match files in pgsql directory.

## Set-up backups

10) To configure daily database backups:
a) As root, execute:
   crontab /home/(sandbox | mapper)/labeller/pgsql/crontabSetup.root
b) Set permissions to 600 for /home/sandbox/labeller/pgsql/pgpassfile_* and 
   /home/mapper/labeller/pgsql/pgpassfile_* .
c) For ease of execution of DB scripts, as users sandbox and mapper, copy 
   /home/sandbox/labeller/pgsql/pgpassfile_sandbox and /home/mapper/labeller/pgsql/pgpassfile_mapper 
   (respectively) to ~/.pgpass . 
