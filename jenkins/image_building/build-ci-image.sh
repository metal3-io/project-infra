#!/usr/bin/env bash

set -eux

export IMAGE_OS="${IMAGE_OS}"

current_dir="$(dirname "$(readlink -f "${0}")")"

# Disable needrestart interactive mode
sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf   > /dev/null

sudo apt-get update

# Install packages
sudo apt-get install python3-pip qemu qemu-kvm -y
sudo pip3 install diskimage-builder python-openstackclient

export ELEMENTS_PATH="${current_dir}/dib_elements"
export DIB_DEV_USER_USERNAME="metal3ci"
export DIB_DEV_USER_PWDLESS_SUDO="yes"
export DIB_DEV_USER_AUTHORIZED_KEYS="${current_dir}/id_ed25519_metal3ci.pub"

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
  export DIB_RELEASE=jammy
else
  export DIB_RELEASE=9
fi 

# Set image names
commit_short="$(git rev-parse --short HEAD)"
img_date="$(date --utc +"%Y%m%dT%H%MZ")"

final_ci_img_name="metal3-ci-${IMAGE_OS}"
ci_img_name="${final_ci_img_name}-${img_date}-${commit_short}"

# Create an image
disk-image-create --no-tmpfs -a amd64 "${IMAGE_OS}"-ci "${IMAGE_OS}" -o "${ci_img_name}" block-device-efi

# Push image to openstack
openstack image create "${final_ci_img_name}" --file "${ci_img_name}".qcow2 --disk-format=qcow2
