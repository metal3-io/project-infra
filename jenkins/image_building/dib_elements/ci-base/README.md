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
* [cloud-init-datasources](https://opendev.org/openstack/diskimage-builder/src/branch/master/diskimage_builder/elements/cloud-init-datasources)

## Pre-installed e2e tooling

`post-install.d/70-install-e2e-tools` bakes the CAPM3 e2e tools into every
`*-ci` image so they are not downloaded during the test run. The corresponding
`cluster-api-provider-metal3` `hack/` scripts are idempotent and become no-ops
when the pinned version is already present.

| Tool | Default version | Override variable |
|------|-----------------|-------------------|
| Go | `1.26.4` | `GO_VERSION` |
| kind | `v0.20.0` | `KIND_VERSION` |
| kubectl | `v1.37.0` | `KUBERNETES_VERSION` |
| vbmctl | `v0.14.0` | `VBMCTL_VERSION` |

### Download integrity

The download URLs are versioned but not content-addressed, so they do not pin
the bytes. Artifacts are therefore compared against the SHA-256 that upstream
publishes for that exact version and architecture, before anything is unpacked
or installed as root:

| Tool | Digest source |
|------|---------------|
| Go | `<tarball URL>.sha256` |
| kind | `<binary URL>.sha256sum` release asset |
| kubectl | `<binary URL>.sha256` |
| vbmctl | none published upstream, not verified; see below |

#### vbmctl

vbmctl is **not** integrity checked. The baremetal-operator release publishes no
checksum for it in any form, so there is nothing to fetch and compare, and no
expected digest is carried in the script for now. That download is trusted on
the strength of HTTPS alone. Once upstream publishes a checksum, it should move
to the same fetch-and-compare path as the other tools.

That release also only ships `vbmctl-linux-amd64`, so arm64 image builds fail on
that download.
