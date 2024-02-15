# centos-ci element

## Overview

**centos-ci** element installs packages and makes configuration changes
specifically for centos-ci images. This element consists of two
shell scripts:  ***install*** which runs during the install.d phase, and
***configure***  which runs during the post-install.d phase.

## Depends

* [centos](https://docs.openstack.org/diskimage-builder/latest/elements/centos/README.html)
* ci-base
