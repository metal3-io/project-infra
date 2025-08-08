# leap-ci element

## Overview

**leap-ci** element installs packages and makes configuration changes
specifically for leap-ci images. This element consists of two
shell scripts:  ***install*** which runs during the install.d phase, and
***configure***  which runs during the post-install.d phase.

## Depends

* [opensuse](https://docs.openstack.org/diskimage-builder/latest/elements/opensuse/README.html)
* ci-base
