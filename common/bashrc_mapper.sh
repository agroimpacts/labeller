## This needs to be sourced from the account's .bashrc file

# These values needed to develop mapper and execute python scripts.
umask 0007
export PYTHONPATH="$HOME/labeller/common"

# Mapper Terraform vars
export TF_VAR_s3_log_uri=s3://activemapper/logs
export TF_VAR_key_name=azavea-mapping-africa
export TF_VAR_s3_rpm_uri=s3://activemapper/rpms/4ff6e43910188a1215a1474cd2e5152e200c5702
export TF_VAR_s3_notebook_uri=s3://activemapper/notebooks
export TF_VAR_bs_bucket=activemapper
export TF_VAR_bs_prefix=bootstrap-cluster-test
export PATH=~/labeller/terraform:$PATH
