<!-- cSpell:ignore oracleoci oraclevd oraclevda oraclevdb -->
<!-- cSpell:ignore udev paravirtualized diskimage scsi vdb vda sysfs -->

# oci-storage element

## Overview

The **oci-storage** element adds OCI consistent device paths to a node image.
It installs one udev rule and one helper script. Together they create the
`/dev/oracleoci/oraclevd*` symbolic links. OCI tooling makes these links on
Oracle images. This element makes them on a custom image.

The OCI Block Volume CSI driver needs these links. The driver mounts a
PersistentVolume only after the link exists. Without the element, the block
volume attaches to the instance as `/dev/sdb`, but the
`/dev/oracleoci/oraclevdb` link does not appear. The mount then fails with
`Failed to wait for device to exist`. A pod that uses a PVC stays `Pending`.

Oracle enables consistent device paths by default only on Oracle images. You
must enable them on a custom image. See
[Connecting to Volumes With Consistent Device Paths](https://docs.oracle.com/en-us/iaas/Content/Block/References/consistentdevicepaths.htm).

## What it installs

* `/etc/udev/rules.d/70-oci-consistent-device-paths.rules` — This rule starts
  the helper for each OCI virtio or SCSI block device.
* `/usr/local/sbin/oci-consistent-device-path` — This helper finds the OCI slot
  of a block device. It prints the matching `oraclevd*` name. udev makes the
  link for the whole disk and for each partition.

For each udev event, the helper reads the SCSI address `H:C:T:L` from
`/sys/block/<dev>/device` and derives the suffix from its LUN: LUN 1 = `a`,
LUN 2 = `b`, LUN 26 = `z`, LUN 27 = `aa`, and LUN 32 = `af`. Oracle documents
the device-path names `a` through `af` for up to 32 volume attachments, and its
example confirms that LUN 2 maps to `oraclevdb`.

The StorageClass used here is `attachment-type: paravirtualized`, where OCI
varies the LUN. If it ever switches to iSCSI, OCI varies the target instead, so
the field that carries the slot must be re-evaluated.

The link names follow the documented OCI scheme. The boot volume is
`oraclevda`. The first data volume is `oraclevdb`. The next is `oraclevdc`.
Partitions take a suffix, for example `oraclevdb1`.

## Depends

* [install-static](https://docs.openstack.org/diskimage-builder/latest/elements/install-static/README.html)
  — This element copies the `static/` tree into the image. It keeps the file
  mode.
