# Save out full probability map

In order to save out the full probability map for an AOI, there are a few things to do. Because this work need to change config.yaml and emr.tf file, it is not recommended to do under mapper user. It is too dangerous to crash everything. So I assume this should be done under a personal user.

Before to start everything, here are some changes to switch the instance from iteration mode to full-probability mode:

- Change the S3 directory for the probability maps.
- Change the emr.tf file to use `--output-all-images` and remove the step `run_DB_insert.py`.

## Steps
### Set up Github for the user

When first time to login in the personal user, there is no Github setting. So the first step is to set up the Github to make sure you can use this instance to clone the Github. The details can be found [here](https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/).

From your local machine
```bash
ssh into user@<instance-name>.crowdmapper.org
```

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

Then it will ask you the path for key files. I recommend to use /home/user/key, because if not there might be permission issue.

**Note:** Don't set the password.

Then:

```bash
eval "$(ssh-agent -s)"
ssh-add /home/user/key (path to the key file)
vim /home/user/key.pub (path to the public key file, dont forget the .pub)
```

Then do:

- Go to Github user - Setting - SSH and GPG keys- New SSH key
- Copy the copied public key there

### Pull mapper repo

All set, now pull the mapper repo to the instance.
```bash
git clone git@github.com:agroimpacts/mapperAL.git mapper
```

### Set up the emr.tf and variables.tf for CVML

Run this (note that all user names, keys and passwords are stripped out here and denoted with user, key and pw)([details](running-mapper-in-production.md)):

```bash
python common/fire_up_mapper.py --ec2_instance "ghana0" --run_id 0 --aoi_id "start" --github_branch "master" --worker_type "m4.xlarge" --bid_price 0.086 --worker_count 80 --bucket "activemapper" --number_outgoing_names 20 --security_group_id "sg-ac924ee6" --secret_key "<key>"  --db_user "<user>" --db_pwd "<pw>" --github_token "<key>" --api_key "<key>" --aws_access "<key>" --aws_secret "<key>" --aws_region "us-east-1"
```

### Download the config file

We can generate the new one according to [running-mapper-in-production](running-mapper-in-production.md) here, but not recommended. Because it might make conflicts with mapper. It is safe to grab the config yaml file from S3 based on instance (mapper0 as an example below):

```bash
aws s3 cp s3://activemapper/config_GH0421189_GH0493502.yaml $HOME/mapper/common/config.yaml
```

**Note:** this step need to set the aws configure first:

```bash
pip install aws
aws configure
<insert the keys you are asked>
```

Now the personal user on this instance has the correct config.yaml to use. 

### Update the files to run CVML for full probability maps

```bash
python common/last_day_on_fly.py
```

## Ready for working!

```bash
python common/run_cvml.py
```

## Get the final map

You probably will wait for a while: 1 - 2 hours depend on the size of AOI. After the instance terminated itself. All the images are in S3 bucket already: activemapper/classified-images/aoiid_whole.

### Read all images and mosaic

For this step, two options:

1. Download all images and mosaic them in software

2. Use this chunk to do so:

**Note:** might have memery issue.

```{r}
library(aws.s3)
library(dplyr)
library(raster)
prob_images <- get_bucket_df("activemapper",
                             prefix="classified-images/GH0335210_GH0366362_whole") %>%
  dplyr::select(Key)

prob <- raster(file.path("/vsis3", 
                         "activemapper", 
                         prob_images$Key[1]))
for (key in prob_images$Key[-1]) {
  img <- raster(file.path("/vsis3", 
                          "activemapper", 
                          key))
  prob <- merge(prob, img)
}
writeRaster(prob, "path")
```

3. Of course you can use other methods.



