# ubuntu-node element

## Overview

**ubuntu-node** element installs packages and makes configuration changes
specifically for ubuntu-node images. This element consists of two
shell scripts:  ***install*** which runs during the install.d phase, and
***configure***  which runs during the post-install.d phase.

## Depends

* [ubuntu](https://docs.openstack.org/diskimage-builder/latest/elements/ubuntu/README.html)
* [base](https://docs.openstack.org/diskimage-builder/latest/elements/base/README.html)
* [vm](https://docs.openstack.org/diskimage-builder/latest/elements/vm/README.html)
* [devuser](https://docs.openstack.org/diskimage-builder/latest/elements/devuser/README.html)
* [openssh-server](https://docs.openstack.org/diskimage-builder/latest/elements/openssh-server/README.html)
* [modprobe](https://docs.openstack.org/diskimage-builder/latest/elements/modprobe/README.html)
* [package-installs](https://docs.openstack.org/diskimage-builder/latest/elements/package-installs/README.html)
