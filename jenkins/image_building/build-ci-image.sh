#!/usr/bin/env bash

set -eux

delete_old_images() {

  # We keep last RETENTION_NUM of metal3ci images and delete old ones when new image has been pushed
  # Example name for metal3ci image: metal3-ci-ubuntu-20240306T0701Z-7b988cb
  RETENTION_NUM=5

  # Delete outdated old images and keep last RETENTION_NUM
  mapfile -t < <(openstack image list  -f json | \
    jq .[].Name | \
    sort -r |\
    grep "metal3ci-${IMAGE_OS}-" | \
    sed 's/"//g')

  for ((i="${RETENTION_NUM}"; i<${#MAPFILE[@]}; i++)); do
    openstack image set "${MAPFILE[i]}" --deactivate
    openstack image delete "${MAPFILE[i]}" 
    echo "${MAPFILE[i]} has been deleted!"
  done
}

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
ci_img_name="metal3ci-${IMAGE_OS}-${img_date}-${commit_short}"

# Create an image
disk-image-create --no-tmpfs -a amd64 "${IMAGE_OS}"-ci "${IMAGE_OS}" -o "${ci_img_name}" block-device-efi

# Keep latest N number of images and delete old ones

# Push image to openstack Kna region
openstack image create "${ci_img_name}" --file "${ci_img_name}".qcow2 --disk-format=qcow2

# delete old images for Kna region (keeps latest five)
delete_old_images

# Push image to openstack Fra region
export OS_AUTH_URL="https://fra1.citycloud.com:5000"
export OS_REGION_NAME="Fra1"
openstack image create "${ci_img_name}" --file "${ci_img_name}".qcow2 --disk-format=qcow2

# delete old images for F region (keeps latest five)
delete_old_images
