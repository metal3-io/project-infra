#!/usr/bin/env bash

set -eux

current_dir="$(dirname "$(readlink -f "${0}")")"
REPO_ROOT="$(realpath "${current_dir}/../..")"

cleanup() {
  deactivate || true
  sudo rm -rf "${REPO_ROOT}/${img_name}.d"
  sudo rm -rf "${current_dir}/venv"
}

trap cleanup EXIT

# Make sure we run everything in the repo root
cd "${REPO_ROOT}" || true

export IMAGE_OS="${IMAGE_OS}"
export IMAGE_TYPE="${IMAGE_TYPE}"

# Disable needrestart interactive mode
sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf > /dev/null || true

sudo apt-get update
sudo apt-get install -y python3-dev python3-pip python3-venv qemu qemu-kvm
python3 -m venv venv

# shellcheck source=/dev/null
. venv/bin/activate
pip install --no-cache-dir diskimage-builder==3.33.0

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
  export KUBERNETES_VERSION="${KUBERNETES_VERSION:-"v1.33.0"}"
  export CRIO_VERSION="${CRIO_VERSION:-"v1.32.3"}"
  export CRICTL_VERSION="${CRICTL_VERSION-"v1.33.0"}"
  img_name="${IMAGE_OS^^}_${numeric_release}_NODE_IMAGE_K8S_${KUBERNETES_VERSION}"
else
  commit_short="$(git rev-parse --short HEAD)"
  img_date="$(date --utc +"%Y%m%dT%H%MZ")"
  img_name="metal3${IMAGE_TYPE}-${IMAGE_OS}-${img_date}-${commit_short}"
fi

export HOSTNAME="${img_name}"

disk-image-create --no-tmpfs -a amd64 -o "${img_name}".qcow2 "${IMAGE_OS}"-"${IMAGE_TYPE}" block-device-efi

echo "${img_name}" > "${REPO_ROOT}/image_name.txt"
