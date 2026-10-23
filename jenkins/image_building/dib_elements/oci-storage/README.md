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

The helper reads the SCSI address `H:C:T:L` from sysfs
(`/sys/block/<dev>/device`). sysfs has the new device when the `add` event
starts, so there is no hot-attach race. The helper then maps the letter from the
SCSI LUN, absolute: boot = LUN 1 = `a`, LUN 2 = `b`, and so on (letter = LUN -
1). The LUN belongs to the volume's attachment slot, not to its neighbors, so
the letter is stable across detach and reattach: freeing LUN 2 and later reusing
it gives back `oraclevdb`, which matches OCI. A rank over the disks present at
the time would instead renumber the survivors when a middle slot frees.

The StorageClass used here is `attachment-type: paravirtualized`, where OCI
varies the LUN. If it ever switches to iSCSI, OCI varies the target instead, so
the field that carries the slot must be re-evaluated.

The link names follow the OCI scheme. The boot volume is `oraclevda`. The first
data volume is `oraclevdb`. The next is `oraclevdc`. Partitions take a suffix,
for example `oraclevdb1`.

## Depends

* [install-static](https://docs.openstack.org/diskimage-builder/latest/elements/install-static/README.html)
  — This element copies the `static/` tree into the image. It keeps the file
  mode.
