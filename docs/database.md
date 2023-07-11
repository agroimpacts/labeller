[Back to README](../README.md)

# learner's database

`learner` connects to a postgres/postgis database, named ___Africa___. 

## Tables

The following are the names of primary tables in the order in which they appear in AfricaSandbox. There are a number of others appearing in the current version of the database that are not listed here, as these are development dross that are not used directly by `learner`. 

Tables that are related to `learner`'s functioning are indicated by an *. 

- __assignment_data__: Stores information on individual assignments completed by workers, including start and completion times, accuracy, HIT ids, etc. 

- __assignment_history__: Tracks assignments and details of related payments for each worker, which is used by assignment review interface that can be accessed by individual workers. 

- __configuration__: Parameters called on by a variety of `learner`'s processes.

- __error_data__: Contains scoring components output from `kml_accuracy`, the accuracy assessment function that is invoked when learner's complete a quality (Q) assessment site. (Current table is in process of being replaced to reflect changes to scoring procedure).

- __hit_data__: Records information about HITs (human intelligence tasks), such as creation and deletion times. Note: A HIT is defined mapping task, which can be undertaken by one or more workers, whereas an assignment is an individual worker's mapping efforts for a given HIT. 

- __incoming_names*__: Table that is populated by `learner`, which sends the names of new grid cells that need to be mapped by workers. 

- __kml_data__: Records the names of grid cells that are queued up for HIT creation, including the type of HIT (Q, F, N, or I) and how many times the HIT created for that sites has been mapped. 

- __kml_data_static__: Contains the names of cells that serve as Q (quality control) and I (initial qualification) HITs. These are in a separate table to preserve them in order to populate the production database's __kml_data__, which is initially empty.

- __master_grid*__: Contains the 0.005$^\circ$ reference grid covering Africa, including the unique name (two-letter country code plus country grid cell number), x and y coordinates of centroid, and (still being added) start and end months of the dry and wet seasons. 

- __qaqcfields__: Contains the reference geometries for Q sites, which are read in by `kml_accuracy` to score a worker's maps.

- __qual_error_data__: Serves the same role as __error_data__, but for qualification (I) sites.  

- __qual_user_maps__: Stores the geometries created by workers during their initial qualification tests (I).

- __roles__: Defines the specific roles of platform users. 

- __scene_data*__: Currently empty table designed to hold information (e.g. provider name, scene ID) about the satellite imagery that is referenced to each grid cell in __master_grid__ (i.e. the imagery that `learner` will classify and the learners will interpret). This should probably be combined with ___WMS_data___ (see below).

- __spatial_ref_sys__: A postgis table containing spatial references. 

- __system_data__: Tracks the current values of certain parameters that are dynamically updated by `learner`, such as the gid of the most recently created Q HIT. 

- __user_invites__: Records the details of invitations sent to join the platform.

- __user_maps__: Geometries created by workers for F, N, and Q assignments. These are ultimately converted to the labels used to train `learner`.

- __users__: Details of registered platform users. 

- __user_roles__: Cross-references user IDs with their roles. 

- __worker_data__: Tracks moving averages of workers' quality scores, which is used to assess bonus payments. 

[Back to README](../README.md)