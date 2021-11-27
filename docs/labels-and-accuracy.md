# Accuracy protocols and consensus labelling

## Accuracy assessment

`mapper` has a built-in procedure for assessing mappers' accuracy against known reference maps. `mapper`'s database contains a set of reference sites (known as Q sites) that are listed in the __kml_data__ table, with field boundaries stored in __qaqcfields__ (except for sites having no fields in them). 

The frequency with which workers are served Q sites in a normal mapping flow is determined by a parameter in the __configuration__ table, which is used by `create_hit_daemon.py`.  

One a worker is served and completes a Q site, `KMLAccuracyCheck.R` which use several custom library functions to do a map comparison of the worker's map to the reference maps. Several accuracy dimensions are assessed, which are assembled into an overall "quality" score that is associated with each the returned assignment. A running average of the last 5 accuracy score is kept for each work as a means for determining bonus payments. The average of all quality scores across the worker's full mapping history can be used as measure of confidence in any map produced by that worker. 

## Consensus labels

To create labels for either i) training `cvml` or ii) developing new reference maps for evaluating worker accuracy, a process of Bayesian merging (developed by Su Ye) is used. When X (typically 5) workers have mapped a site, it is converted into a consensus "label" by `consensus_map_generator.R`. 

Consensus labelling is used in production to convert F type assignments for `cvml` into consensus labels for training the machine learning classifier. `generate_consensus_daemon.py` monitors the progress of the latest batch of F sites to come through from `cvml`, and processes them upon satisfactory completion by the required number of workers. Longer-term, it will be combined with a segmentation algorithm to back out individual fields from the consensus labels, which will be used to define distinct field objects (masks) for training a CNN, and/or to create new field polygons that can serve as reference maps.  The second case is likely to be applied on an as-needed basis to N type assignments. 