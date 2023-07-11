# labeller

The crowdsourcing platform for collecting training data and initiating the ML process within the active learning framework. 

This version evolved from the original version called `DIYlandcover` (Estes et al, 2016), that was designed to connect to Amazon's Mechanical Turk workforce. It was re-engineered into `mapper`, a standalone version with its own worker interface and (simple) management system.  `labeller` is a lightweight version of `mapper`, renamed to better describe its purpose. 

## Overview

Documentation is in the process of being updated. Here are a few pointers to some of it. 

- A description of [labeller's components](docs/mapper-design.md), as originally designed.

- A description of `labeller`'s [database](docs/database.md).

- How `labeller` and `learner` [interact](docs/interactivity-design.md) in the active learning process. 

- Image acquisition and processing

- Segmentation

## Building

- Building a `labeller` instance from [scratch](docs/build-labeller.md)

- [Cloning](docs/create-ami.md) an existing `labeller` instance and using that to create a [new instance](docs/setting-up-new-labeller-instance.md)