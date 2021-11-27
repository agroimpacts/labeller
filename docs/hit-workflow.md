## HIT Types and the Active Learning Workflow

There are four types of assignments that can be considered by `mapper`:

- I: These are a small number (currently 8) of initial qualification sites that any worker joining `mapper` has to pass before mapping the other three kinds.
- F: Training sites for `cvml`. These are either selected at random by `mapper` (from the total pool of sites to be classified) for `cvml`'s initial training, or by `cvml` itself on subsequent iterations, based on classification uncertainty. ___Etmyology:___ Originally the letter stood for Future under the old Mechanical Turk system (sites to be mapped by multiple workers so that they could eventually be merged to create new reference maps for Q HITs). 
- N: Sites given to workers when all F sites are complete, while waiting for the next batch of F sites to come back from `cvml`. ___Etmyology:___ Originally standing for normal (under the old Mechanical Turk system) mapping jobs, these were served out to just a single worker.    
- Q: Quality assessment sites, where workers' mapping accuracy is scored. 

Workers are served F/N/Q sites at a frequency determined by the parameters "Hit_QaqcPercentage" and "Hit_FqaqcPercentage" in mapper's __config__ table. There are two modes: 

1. Hit_Standalone = True: `mapper` operates in the original standalone way and serves up a randomly selected F, Q, or N sites based on the ratio: 

    -  Hit_FaqcPercentage/(100-Hit_FaqcPercentage-Hit_QaqcPercentage)/Hit_QaqcPercentage
<br><br>

2. Hit_Standalone = False: `mapper` prioritizes F sites (the mode for working with `cvml`). An F or Q is randomly selected and served to the worker based on the ratio: 

    - (100-Hit_QaqcPercentage)/Hit_QaqcPercentage
    <br><br>

    Thus F sites are prioritized, and N sites are only offered to a worker once the worker has completed all F sites in the system.  
    
## Flow of HITs

This describes the flow of HITs when `mapper` and `cvml` are connected in the active learning framework. I type HITs are not explicitly mentioned because they have no effect on what `cvml` does.  

1. The pool of sites (cells in __master_grid__) that are to be classified by `cvml` is defined (through an offline process). These sites are registered in the __master_grid__ table by setting their "avail" field to "F". Their names must be cross-referenced with the __scene_data__table to ensure that the selected names also have corresponding imagery for i) cvml to process and ii) workers to label.

2. `initial_f_sites.py` selects an initial random draw from master_grid from the list of sites where avail = "F". (__Note__: Code has to be revised to do this). 

3. These sites are mapped by workers, converted to [consensus labels](labels-and-accuracy.md) by `generate_consensus_daemon.py`, and then sent to an s3 bucket where they become the initial training set for `cvml`. That is, these are sites that have both images and labels associated with them. 

4. After its first train/test/evaluate uncertainty cycle, `cvml` selects, from its list of "test" images (images that not in the training set) the n most uncertain predictions, and sends the names of these sites to `mapper`, inserting them directly into the __incoming_names__ table. 

5. The new sites in __incoming_names__ are picked up by `register_f_hits`, and inserted into the __kml_data__ table. 

6. __create_hit_daemon__ prioritizes these for new worker assignments.  

7. When they are completed by workers, they are converted to consensus labels by `generate_consensus_daemon.py` and then sent back to s3, where they are added into the pool of training labels.  

    - N sites will start being served to workers by `mapper` as soon as a worker has no more F sites available to map. F HITs will persist in the system until they are mapped by the number of workers listed in th "Hit_MaxAssignmentsF" __configuration__ parameter. 

8. Another iteration of `cvml` begins. teps 4-7 repeat until a pre-determined accuracy cutoff is reached (under development). 





