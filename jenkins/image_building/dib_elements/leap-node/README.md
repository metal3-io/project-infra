# leap-node element

## Overview

**leap-node** element installs packages and makes configuration changes
specifically for leap-node images. This element consists of three
shell scripts:  ***setup-repos*** which runs during the pre-install.d phase,
and ***install***  which runs during the install.d phase. Finally
***pre-pull-images*** which runs during the post-install step.

## Depends

* [opensuse](https://docs.openstack.org/diskimage-builder/latest/elements/opensuse/README.html)
* [base](https://docs.openstack.org/diskimage-builder/latest/elements/base/README.html)
* [vm](https://docs.openstack.org/diskimage-builder/latest/elements/vm/README.html)
* [devuser](https://docs.openstack.org/diskimage-builder/latest/elements/devuser/README.html)
* [openssh-server](https://docs.openstack.org/diskimage-builder/latest/elements/openssh-server/README.html)
* [package-installs](https://docs.openstack.org/diskimage-builder/latest/elements/package-installs/README.html)
* [cloud-init-datasources](https://docs.openstack.org/diskimage-builder/latest/elements/cloud-init-datasources/README.html)
