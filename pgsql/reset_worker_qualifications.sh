#! /bin/bash

# revoke and grant again worker qualifications
read -s -p "Enter postgis password: " postgis_pw
echo

declare -a tablearray
while IFS=$'\n' read -r line_data; do
    tablearray[i]="${line_data}"
    ((++i))
done < <(PGPASSWORD=$postgis_pw psql -U postgis Africa -t -c "select email from users where id in \
(select worker_id from worker_data);")

echo "Revoking and granting qualifications for workers"
for item in ${tablearray[*]}
do
    python $HOME/labeller/common/tools/revokeQualification.py $item
    python $HOME/labeller/common/tools/grantQualification.py $item
done

