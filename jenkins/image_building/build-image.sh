#!/usr/bin/env bash

set -eux

current_dir="$(dirname "$(readlink -f "${0}")")"
REPO_ROOT="$(realpath "${current_dir}/../..")"

cleanup() {
  deactivate || true
  sudo rm -rf "${REPO_ROOT}/${img_name}.d"
  sudo rm -rf "${current_dir}/dib"
}

trap cleanup EXIT

# Make sure we run everything in the repo root
cd "${REPO_ROOT}" || true

export IMAGE_OS="${IMAGE_OS}"
export IMAGE_TYPE="${IMAGE_TYPE}"

# shellcheck disable=SC1091
source "${current_dir}/upload-ci-image.sh"

# Disable needrestart interactive mode
sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf > /dev/null || true

sudo apt-get update
sudo apt-get install python3-pip qemu qemu-kvm -y
sudo pip3 install diskimage-builder python-openstackclient
sudo -H pip install virtualenv

# sudo pip3 install diskimage-builder python-openstackclient
mkdir "${current_dir}/dib"
pushd "${current_dir}/dib"
virtualenv env
# shellcheck disable=SC1091
source env/bin/activate

git clone https://opendev.org/openstack/diskimage-builder || true
cd diskimage-builder
git checkout 3.33.0
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

disk-image-create --no-tmpfs -a amd64 -o "${img_name}".qcow2 "${IMAGE_OS}"-"${IMAGE_TYPE}" block-device-efi

if [[ "${IMAGE_TYPE}" == "node" ]]; then
  echo "${img_name}" > "${REPO_ROOT}/image_name.txt"
else
  upload_ci_image_cleura "${img_name}"
  upload_ci_image_xerces "${img_name}"
fi
