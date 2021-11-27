# labeller

A platform for collecting data for training and validation machine learning models used to map land cover. `labeller` was designed to interact with an ML model within an active learning framework. 

This version evolved from the original version called `DIYlandcover` (Estes et al, 2016), that was designed to connect to Amazon's Mechanical Turk workforce. It was re-engineered into `mapper`, a standalone version with its own worker interface and (simple) task management system.  `labeller` is a lighter-weight version of `mapper`, renamed to better describe its purpose. 

## Overview

Documentation is in the process of being updated. Here are a few pointers to some of it. 

- A description of [labeller's components](docs/mapper-design.md), as originally designed.

- A description of `labeller`'s [database](docs/database.md).

- How `labeller` and `learner` [interact](docs/interactivity-design.md) in the active learning process. 

## Building

- Building a `labeller` instance from [scratch](docs/build-labeller.md)

- [Cloning](docs/create-ami.md) an existing `labeller` instance and using that to create a [new instance](docs/setting-up-new-labeller-instance.md)

### Citation

Estes, L.D., Ye, S., Song, L., Luo, B., Eastman, J.R., Meng, Z., Zhang, Q., McRitchie, D., Debats, S.R., Muhando, J., Amukoa, A.H., Kaloo, B.W., Makuru, J., Mbatia, B.K., Muasa, I.M., Mucha, J., Mugami, A.M., Mugami, J.M., Muinde, F.W., Mwawaza, F.M., Ochieng, J., Oduol, C.J., Oduor, P., Wanjiku, T., Wanyoike, J.G., Avery, R. & Caylor, K. (2021) High resolution, annual maps of the characteristics of smallholder-dominated croplands at national scales. EarthArxiv https://doi.org/10.31223/X56C83


### Acknowledgements

The primary support for this work was provided by Omidyar Network’s Property Rights Initiative, now PLACE, with initial support from NASA (80NSSC18K0158), the National Science Foundation (SES-1801251; SES-1832393), and Princeton University. Computing support was provided by the AWS Cloud Credits for Research program and the Amazon Sustainability Data Initiative. Azavea provided significant contributions in engineering the connections between labeller and [learner](https://github.com/agroimpacts/learner).