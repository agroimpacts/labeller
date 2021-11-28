#! /bin/bash

psql -U postgis AfricaSandbox <<EOD
\pset fieldsep ''
\pset format unaligned
\pset tuples_only
\o updateConfigurationSandbox.sql
select '-- ', comment, '
UPDATE configuration SET value = ''', value, ''' WHERE key = ''', key, ''';' from configuration order by key;
EOD
#cp -p updateConfigurationSandbox.sql updateConfiguration.sql
