# The code to set up labeller's pgpass files and a sql statement file
import yaml
import os

home = os.environ['HOME']
if home not in {'/home/mapper', '/home/sandbox'}: 
    projectRoot = os.getcwd()  # allows testing locally
else:
    projectRoot = '%s/labeller' % home

# Parse yaml file of configuration parameters.
def parseYaml(projectRoot, input_file):
    input_file = "%s/common/%s" % (projectRoot, input_file)
    with open(input_file, 'r') as yaml_file:
        params = yaml.load(yaml_file)
        return params

def fileCreateWrite(file_name, strings_to_write):
    f = open(file_name, "w+")
    for i in strings_to_write:
        f.write("%s\r\n" % (i))
    f.close()
    

# Read parameter file
config = parseYaml(projectRoot, 'config.yaml')

# Create pgpassfile for labeller if it doesn't exist. This file is ignored by git
# because it contains passwords
pgpass_strings = [
  "localhost:5432:*:postgres:%s" % (config['labeller']['dbpg_password']),
  "localhost:5432:Africa:postgis:%s" % (config['labeller']['db_password']),
  "localhost:5432:AfricaSandbox:postgis:%s" % (config['labeller']['db_password'])
]
pgpassfile_mapper = "%s/pgsql/%s" % (projectRoot, 'pgpassfile_mapper')
if os.path.isfile(pgpassfile_mapper) is False: 
  fileCreateWrite(pgpassfile_mapper, pgpass_strings)
  print "Created " + pgpassfile_mapper
  
# Create pgpassfile for sandbox (unclear if this is still needed, done here for
# completeness)
pgpass_strings = [
  "localhost:5432:AfricaSandbox:postgis:%s" % (config['labeller']['db_password']),
  "localhost:5432:AfricaSandbox:postgis:%s" % (config['labeller']['db_password'])
]
pgpassfile_sandbox = "%s/pgsql/%s" % (projectRoot, 'pgpassfile_sandbox')
if os.path.isfile(pgpassfile_sandbox) is False:
  fileCreateWrite(pgpassfile_sandbox, pgpass_strings)
  print "Created " + pgpassfile_sandbox

# Create role_create_su.sql file for database administration
pgpass_strings = [
  "ALTER USER postgres WITH PASSWORD '%s';" % (config['labeller']['dbpg_password']),
  "", 
  "-- Role: postgis",
  "-- DROP ROLE postgis;",
  "CREATE ROLE postgis LOGIN", 
  "  SUPERUSER INHERIT CREATEDB NOCREATEROLE NOREPLICATION;",
  "ALTER USER postgis WITH PASSWORD '%s';" % (config['labeller']['db_password'])
]
role_create_su_file = "%s/pgsql/%s" % (projectRoot, 'role_create_su.sql')
if os.path.isfile(role_create_su_file) is False:
    fileCreateWrite(role_create_su_file, pgpass_strings)
    print "Created " + role_create_su_file
