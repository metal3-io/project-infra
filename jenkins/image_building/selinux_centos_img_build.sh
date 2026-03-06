#!/usr/bin/env bash

# This script is used to build and insert an SELinux module on centos CI
# hosts so that the hosts can use DIB to build images.
set -eux

cat > setfilesmac_chroot.te <<'EOF'
module setfilesmac_chroot 1.0;
require { type cloud_init_t; type setfiles_mac_t; class process transition; }
allow cloud_init_t setfiles_mac_t:process transition;
EOF
# Building selinux module
checkmodule -M -m -o setfilesmac_chroot.mod setfilesmac_chroot.te
semodule_package -o setfilesmac_chroot.pp -m setfilesmac_chroot.mod
# Inserting selinux module
sudo semodule -i setfilesmac_chroot.pp
