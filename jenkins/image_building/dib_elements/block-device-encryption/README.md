# Block Device Encryption

This provides a block-device configuration for the `vm` element to get a
multi-partition disk suitable for EFI based booting with support to full disk
encryption.

Note on x86 this provides the extra BIOS boot partition and a EFI boot partition
for maximum compatibility.

This element requires `mkfs.vfat` command to be available on the build system,
usually included in the `dosfstools` OS package.
