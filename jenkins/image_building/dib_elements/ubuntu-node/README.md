# ubuntu-node element

## Overview

**ubuntu-node** element installs packages and makes configuration changes
specifically for ubuntu-node images. This element consists of three
shell scripts:  ***setup-repos*** which runs during the pre-install.d phase,
and ***install***  which runs during the install.d phase. Finally
***pre-pull-images*** which runs during the post-install step.

Note that cloud-init datasource defaults to EC2 exclusivley.
Which is different from a fresh Ubuntu installation that usally has all
different options. This can be set with env variable `DIB_CLOUD_INIT_DATASOURCES`.
See cloud-init element documentation for more information
[cloud-init documentation](https://docs.openstack.org/diskimage-builder/latest/elements/cloud-init/README.html)

## Depends

* [ubuntu](https://docs.openstack.org/diskimage-builder/latest/elements/ubuntu/README.html)
* [base](https://docs.openstack.org/diskimage-builder/latest/elements/base/README.html)
* [vm](https://docs.openstack.org/diskimage-builder/latest/elements/vm/README.html)
* [devuser](https://docs.openstack.org/diskimage-builder/latest/elements/devuser/README.html)
* [openssh-server](https://docs.openstack.org/diskimage-builder/latest/elements/openssh-server/README.html)
* [modprobe](https://docs.openstack.org/diskimage-builder/latest/elements/modprobe/README.html)
* [package-installs](https://docs.openstack.org/diskimage-builder/latest/elements/package-installs/README.html)
