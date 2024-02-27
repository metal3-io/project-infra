# ubuntu-ci element

## Overview

**ubuntu-ci** element installs packages and makes configuration changes
specifically for ubuntu-ci images. This element consists of two
shell scripts:  ***install*** which runs during the install.d phase, and
***configure***  which runs during the post-install.d phase.

## Depends

* [ubuntu](https://docs.openstack.org/diskimage-builder/latest/elements/ubuntu/README.html)
* ci-base

ubuntu-ci element installs packages and makes configuration changes
specifically for Ubuntu-ci images. This element consists of two shell scripts:
install, which runs during the install.d phase, and configure, which runs
during the post-install.d phase.
