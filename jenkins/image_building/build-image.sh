#!/usr/bin/env bash

set -eux

export IMAGE_OS="${IMAGE_OS}"
export IMAGE_TYPE="${IMAGE_TYPE}"

current_dir="$(dirname "$(readlink -f "${0}")")"

# shellcheck disable=SC1091
source "${current_dir}/upload-ci-image.sh"
# shellcheck disable=SC1091
source "${current_dir}/upload-node-image.sh"
# shellcheck disable=SC1091
source "${current_dir}/verify-node-image.sh"

# Disable needrestart interactive mode
sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf > /dev/null || true

sudo apt-get update
sudo apt-get install python3-pip qemu qemu-kvm -y
sudo pip3 install diskimage-builder python-openstackclient
# TODO(Sunnatillo): When newer version than 3.32.0 of disk-image builder released remove changes
# done by this commit.
sudo -H pip install virtualenv

# sudo pip3 install diskimage-builder python-openstackclient
mkdir "${current_dir}/dib"
pushd "${current_dir}/dib"
virtualenv env
# shellcheck disable=SC1091
source env/bin/activate
git clone https://opendev.org/openstack/diskimage-builder
cd diskimage-builder
git checkout 4d1e1712b1448b12b97780c4b4cd962646884abb
sudo pip install --no-cache-dir -e .

popd

export ELEMENTS_PATH="${current_dir}/dib_elements"
export DIB_DEV_USER_USERNAME="metal3ci"
export DIB_DEV_USER_PWDLESS_SUDO="yes"
export DIB_DEV_USER_AUTHORIZED_KEYS="${current_dir}/authorized_keys"

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
  export DIB_RELEASE=jammy
  numeric_release=22.04
else
  export DIB_RELEASE=9
  numeric_release=9
fi

if [[ "${IMAGE_TYPE}" == "node" ]]; then
  # The default data source for cloud-init element is exclusively Amazon EC2
  export DIB_CLOUD_INIT_DATASOURCES="ConfigDrive"
  export KUBERNETES_VERSION="${KUBERNETES_VERSION:-"v1.30.0"}"
  export CRIO_VERSION="${CRIO_VERSION:-"v1.30.0"}"
  export CRICTL_VERSION="${CRICTL_VERSION-"v1.30.0"}"
  img_name="${IMAGE_OS^^}_${numeric_release}_NODE_IMAGE_K8S_${KUBERNETES_VERSION}"
else
  commit_short="$(git rev-parse --short HEAD)"
  img_date="$(date --utc +"%Y%m%dT%H%MZ")"
  img_name="metal3${IMAGE_TYPE}-${IMAGE_OS}-${img_date}-${commit_short}"
fi

export HOSTNAME="${img_name}"

disk-image-create --no-tmpfs -a amd64 -o "${img_name}".raw -t raw "${IMAGE_OS}"-"${IMAGE_TYPE}" block-device-efi

if [[ "${IMAGE_TYPE}" == "node" ]]; then
  verify_node_image "${img_name}"
  echo "Image testing successful."
  upload_node_image "${img_name}"
else
  upload_ci_image_cleura "${img_name}"
  upload_ci_image_xerces "${img_name}"
fi

deactivate
sudo rm -f "${img_name}".{raw,qcow2}
sudo rm -rf "${current_dir}/dib"
