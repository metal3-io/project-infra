<!-- cSpell:ignore oracleoci oraclevd oraclevda oraclevdb -->
<!-- cSpell:ignore udev paravirtualized diskimage scsi vdb vda -->

# oci-storage element

## Overview

**oci-storage** adds OCI (Oracle Cloud Infrastructure) *consistent device
path* support to a node image. It installs a udev rule and helper that create
the `/dev/oracleoci/oraclevd*` symlinks that OCI's tooling normally provides.

This is required for the OCI Block Volume CSI driver to mount PersistentVolumes
on custom images. Without it, a block volume attaches to the instance (visible
as `/dev/sdb`), but the `/dev/oracleoci/oraclevdb` symlink the CSI driver waits
for is never created, so mounting fails with
`Failed to wait for device to exist` and pods that use a PVC stay `Pending`.

Oracle documents that consistent device paths are enabled by default only on
Oracle-provided images and must be enabled explicitly on custom images built
from other sources. See
[Connecting to Volumes With Consistent Device Paths](https://docs.oracle.com/en-us/iaas/Content/Block/References/consistentdevicepaths.htm).

## What it installs

* `/etc/udev/rules.d/70-oci-consistent-device-paths.rules` — triggers the
  helper for every OCI virtio/SCSI block device.
* `/usr/local/sbin/oci-consistent-device-path` — resolves a block device to its
  OCI slot (from the PCI/SCSI `by-path` ordering, boot volume = `a`) and creates
  the matching `/dev/oracleoci/oraclevd*` symlink for the whole disk and each
  partition.

The symlink naming matches OCI's scheme: the boot volume is `oraclevda`, the
first attached data volume is `oraclevdb`, and so on, with partitions suffixed
(`oraclevdb1`, `oraclevdb2`, ...).

## Note

This is the node-image half of the fix. Node images are not pushed to OCI by
this repo, so the imported OCI custom image must also have the *consistent
device paths* capability (`Storage.ConsistentVolumeNaming`) enabled manually,
either in the console (Edit image capabilities) or via
`oci compute image-capability-schema create`.

## Depends

* [install-static](https://docs.openstack.org/diskimage-builder/latest/elements/install-static/README.html)
  — copies this element's `static/` tree into the image, preserving mode.
