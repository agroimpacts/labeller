resource "aws_emr_cluster" "emr-spark-cluster" {
  name          = "GeoPySpark Cluster"
  applications  = ["Hadoop", "Spark", "Ganglia"]
  log_uri       = "${var.s3_log_uri}"
  # Don't use emr version >5.12.1; Spark 2.3 currently incompatible w/ rasterframes
  release_label = "emr-5.12.1"
  service_role  = "${var.emr_service_role}"

  step {
    name="Clone Learner"
    action_on_failure = "CONTINUE"
    hadoop_jar_step {
    jar="command-runner.jar"
    args = ["git", "clone", "--depth", "1", "-b", "master", "https://github.com/agroimpacts/learner.git", "/home/hadoop/learner"]
  }}

  step {
    name="run_geopyspark.py"
    action_on_failure = "CONTINUE"
    hadoop_jar_step {
    jar="command-runner.jar"
    args = ["spark-submit", "--master", "yarn", "--packages", "io.astraea:pyrasterframes:0.7.3-GT2,org.apache.hadoop:hadoop-aws:2.7.3,org.apache.logging.log4j:log4j-core:2.11.1", "--jars", "/opt/jars/geotrellis-backend-assembly-0.4.2.jar", "--conf", "spark.executorEnv.GDAL_DATA=/usr/local/share/gdal", "--conf", "spark.executor.instances=149", "--conf", "spark.executor.cores=5", "--conf", "spark.executor.memory=7g", "--conf", "spark.driver.cores=5", "--conf", "spark.driver.memory=7g", "--conf", "spark.sql.shuffle.partitions=2235", "--conf", "spark.default.parallelism=2235", "/home/hadoop/learner/run_it/run_geopyspark.py", "--config-filename", "config_1.yaml", "--probability-images", "30", "--random-seed", "42", "activemapper", "0", "1"]
  }}

  step {
    name="run_DB_insert.py"
    action_on_failure = "CONTINUE"
    hadoop_jar_step {
    jar="command-runner.jar"
    args = ["python3", "/home/hadoop/learner/run_it/run_DB_insert.py", "--config-filename", "config_1.yaml"]
  }}

  termination_protection = false
  keep_job_flow_alive_when_no_steps = false

  ec2_attributes {
    subnet_id        = "${var.subnet}"
    instance_profile = "${var.emr_instance_profile}"
    key_name         = "${var.key_name}"

    emr_managed_master_security_group = "${var.user_defined_sg == "true" ? var.security_group : aws_security_group.security-group.id}"
    emr_managed_slave_security_group  = "${var.user_defined_sg == "true" ? var.security_group : aws_security_group.security-group.id}"
  }

  instance_group {
    # bid_price      = "${var.bid_price}"
    instance_count = 1
    instance_role  = "MASTER"
    instance_type  = "m3.2xlarge"
    name           = "geopyspark-master"
  }

  instance_group {
    bid_price      = "${var.bid_price}"
    instance_count = "${var.worker_count}"
    instance_role  = "CORE"
    instance_type  = "${var.worker_type}"
    name           = "geopyspark-core"
  }

  bootstrap_action {
    path = "s3://${var.bs_bucket}/${var.bs_prefix}/bootstrap.sh"
    name = "geopyspark"
    args = [
      "${var.s3_rpm_uri}",
      "${var.s3_notebook_uri}",
      "${var.geopyspark_jars}",
      "${var.geopyspark_uri}",
      "${var.rasterframes_sha}",
      "${var.rasterframes_version}"
    ]
  }

  configurations = "cluster-configurations.json"

  depends_on = ["aws_s3_bucket_object.bootstrap"]
}

output "emr-id" {
  value = "${aws_emr_cluster.emr-spark-cluster.id}"
}

output "emr-master" {
  value = "${aws_emr_cluster.emr-spark-cluster.master_public_dns}"
}
