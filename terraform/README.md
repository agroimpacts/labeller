# Terraform Deployment Scripts #

This directory holds the necessary files to start an EMR cluster with
GeoPySpark and Jupyter notebook support.  The minimal commands to build such a
cluster are
```bash
terraform init
terraform apply
```

After following prompts, this will start an EMR cluster running at
`ec2-xxx-xxx-xxx-xxx.compute-1.amazonaws.com`, where the `xxx`s are filled in
the appropriate numerical values displayed on the terminal after successfully
executing the terraform scripts.

Once finished with the cluster, running
```bash
terraform destroy
```
will kill the cluster.

However, following this procedure will result in having to fill in a long list
of parameters each time a terraform action is called for.  Instead, it makes
more sense to set some environment variables to provide a persistent
configuration to terraform.

For every variable block in the `variables.tf`, we supply an environment
variable named as `TF_VAR_variable_name` which will be read in by terraform,
and the user will no longer be prompted for a value.  The list of variables
and a description follows:
 - `TF_VAR_s3_log_uri`: A location on S3 where logs will be written.  Supplied
   in the form `s3://bucket/prefix`.
 - `TF_VAR_subnet`: The AWS subnet to create the cluster in.  From the AWS EMR
   console, go to `VPC subnets` panel, and select a value of the form
   `subnet-xxxxxxxx` and place it in this variable.
 - `TF_VAR_key_name`: The name of an Amazon EC2 key pair associated to the
   account.  See [this
   link](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair)
   if you need to create one.  Note that this allows SSH'ing into the
   resulting cluster with the following command:

       ssh -i <location of saved PEM file> hadoop@ec2-xxx-xxx-xxx-xxx.compute-1.amazonaws.com

 - `TF_VAR_bs_bucket`: The S3 bucket where the bootstrap script will be
   uploaded.  If you wish to upload to `s3://bucket/prefix/path`, this
   value is `bucket`.
 - `TF_VAR_bs_prefix`: The S3 prefix where the bootstrap script will be
   uploaded.  If you wish to upload to `s3://bucket/prefix/path`, this value
   is `prefix/path`.
 - `TF_VAR_s3_rpm_uri`: The S3 path where prebuilt RPMs and wheels are
   available.  See [this
   repository](http://github.com/geodocker/geodocker-jupyter-geopyspark/tree/master/rpms/build)
   for build instructions.
 - `TF_VAR_s3_notebook_uri`: The path on S3 for storing notebooks.  These will
   persist from session to session.

# Starting a CVMLAL Iteration #
Make sure to have text of this form in your .bashrc on the mapper instance. These may change.

```bash
# Mapper Terraform vars
export TF_VAR_subnet=subnet-638f0c39
export TF_VAR_s3_log_uri=s3://activemapper/logs
export TF_VAR_key_name=azavea-mapping-africa
export TF_VAR_s3_rpm_uri=s3://activemapper/rpms/4ff6e43910188a1215a1474cd2e5152e200c5702
export TF_VAR_s3_notebook_uri=s3://activemapper/notebooks
export TF_VAR_bs_bucket=activemapper
export TF_VAR_bs_prefix=bootstrap-cluster-test
export PATH=~/labeller/terraform:$PATH
```

then run

`python run_cvml.py`

This script can be called from anywhere if the .bashrc is properly set. 
