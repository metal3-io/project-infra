# centos-node element

## Overview

**centos-node** element installs packages and makes configuration changes
specifically for centos-node images. This element consists of three
shell scripts:  ***setup-repos*** which runs during the pre-install.d phase,
and ***install***  which runs during the install.d phase. Finally
***pre-pull-images*** which runs during the post-install step.

## Depends

* [centos](https://docs.openstack.org/diskimage-builder/latest/elements/centos/README.html)
* [base](https://docs.openstack.org/diskimage-builder/latest/elements/base/README.html)
* [vm](https://docs.openstack.org/diskimage-builder/latest/elements/vm/README.html)
* [openssh-server](https://docs.openstack.org/diskimage-builder/latest/elements/openssh-server/README.html)
* [modprobe](https://docs.openstack.org/diskimage-builder/latest/elements/modprobe/README.html)
* [package-installs](https://docs.openstack.org/diskimage-builder/latest/elements/package-installs/README.html)
