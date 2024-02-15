# ci-base element

## Overview

This element takes care of installing common packages both for ubuntu and
centos ci images. **ci-base** element utilizes package-installs to declarative
method of installing packages for image build.

## Depends

ci-base element depends following elements.

* [base](https://docs.openstack.org/diskimage-builder/latest/elements/base/README.html)
* [vm](https://docs.openstack.org/diskimage-builder/latest/elements/vm/README.html)
* [devuser](https://docs.openstack.org/diskimage-builder/latest/elements/devuser/README.html)
* [openssh-server](https://docs.openstack.org/diskimage-builder/latest/elements/openssh-server/README.html)
* [pkg-map](https://docs.openstack.org/diskimage-builder/latest/elements/pkg-map/README.html)
* [package-installs](https://docs.openstack.org/diskimage-builder/latest/elements/package-installs/README.html)
