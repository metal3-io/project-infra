# Initrd SDK

The Initrd SDK folder contains scripts and documentation to help integrate
features e.g. LUKS and TPM support into the linux "initrd/initramfs" of disk
images built as part of the Metal3 project.

This directory is just a loose collection of scripts and information that
can be injected at different stages of the image building and would be
eventually executed during the boot process of a machine.

## Initrd environment

Usually in initrd/initramfs images are built with e.g. a tool like `dracut`.
An initrd is required to be as small as possible so it usually lacks any kind
of user space tooling.

## unlock-mount-luks.sh

This is a script that can be injected to initramfs images that were built with
dracut and the script relies on only two external tools `blkid` and
`systemd-cryptsetup`. If an image was built with `dracut` and the `dracut`
module `crypt` is enabled then both `blkid` and `systemd-cryptsetup` should be
present in the initrd environment.

## unseal-and-open-luks.service

This is the systemd service unit file that automatically starts the
`unlock-mount-luks.sh`. This service has to be enabled with `systemctl enable`
during or after the initrd build process.

## verify-realroot.sh

This script is used to provide a controlled wait loop in order to give time
to other systemd services to prepare the root file system. The intention is to
have a deterministic check/wait loop before the initrd root switching is
initiated in order to avoid potential race conditions.

This script has to be executed by the `initrd-switch-root.service` as a
`ExecStartPre` option such as:
`ExecStartPre=/bin/sh -c '/etc/verify-realroot.sh'`
