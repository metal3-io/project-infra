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

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  AGENT_OS="${ID}"
fi

export IMAGE_OS="${IMAGE_OS}"
export IMAGE_TYPE="${IMAGE_TYPE}"

# Jenkins agent OS-specific package installation and configuration
if [[ "${AGENT_OS}" == "ubuntu" ]]; then
  # Disable needrestart interactive mode
  sudo sed -i "s/^#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf > /dev/null || true

  sudo apt-get update
  sudo apt-get install -y python3-dev python3-pip python3-venv qemu-system qemu-utils qemu-kvm

  python3 -m venv venv
elif [[ "${AGENT_OS}" == "centos" ]]; then
  # Install EPEL repository for additional packages
  sudo yum install -y epel-release

  # Install required packages
  sudo yum install -y python3-devel python3-pip qemu-kvm
  sudo pip3 install virtualenv

  python3 -m virtualenv venv
else
  echo "Unsupported AGENT_OS: ${AGENT_OS}"
  exit 1
fi

# shellcheck source=/dev/null
. venv/bin/activate
pip install --no-cache-dir diskimage-builder==3.33.0

export ELEMENTS_PATH="${current_dir}/dib_elements"
export DIB_DEV_USER_USERNAME="metal3ci"
export DIB_DEV_USER_PWDLESS_SUDO="yes"
export DIB_DEV_USER_AUTHORIZED_KEYS="${current_dir}/authorized_keys"

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
  export DIB_RELEASE=noble
  # Setting upstrem Ubuntu 24.04 image
  export DIB_CLOUD_IMAGES="https://cloud-images.ubuntu.com/${DIB_RELEASE}/20250725"
  numeric_release=24.04
else
  numeric_release=9
  # Setting upstrem Centos 9 stream image
  centos_upstream_img="CentOS-Stream-GenericCloud-9-20250811.0.x86_64.qcow2"

  if [[ ! -f "${REPO_ROOT}/${centos_upstream_img}" ]]; then
    wget -O "${REPO_ROOT}/${centos_upstream_img}" "https://cloud.centos.org/centos/9-stream/x86_64/images/${centos_upstream_img}"
  fi
  export DIB_LOCAL_IMAGE="${REPO_ROOT}/${centos_upstream_img}"
fi

if [[ "${IMAGE_TYPE}" == "node" ]]; then
  # The default data source for cloud-init element is exclusively Amazon EC2
  export DIB_CLOUD_INIT_DATASOURCES="ConfigDrive"
  export KUBERNETES_VERSION="${KUBERNETES_VERSION:-"v1.33.0"}"

  if [[ "${PRE_RELEASE:-}" == "true" ]]; then
    # Extract minor version (e.g., "1.34" from "v1.34.0")
    KUBERNETES_MINOR_VERSION=$(echo "${KUBERNETES_VERSION:-"v1.33.0"}" | sed 's/^v//' | cut -d'.' -f1,2)

    # Fetch the latest pre-release Kubernetes version for the minor version
    FETCHED_VERSION=$(curl -L -s "https://dl.k8s.io/release/latest-${KUBERNETES_MINOR_VERSION}.txt")
    export KUBERNETES_VERSION="${FETCHED_VERSION}"
  fi

  export CRIO_VERSION="${CRIO_VERSION:-"v1.32.3"}"
  export CRICTL_VERSION="${CRICTL_VERSION:-"v1.33.0"}"
  img_name="${IMAGE_OS^^}_${numeric_release}_NODE_IMAGE_K8S_${KUBERNETES_VERSION}"
else
  commit_short="$(git rev-parse --short HEAD)"
  img_date="$(date --utc +"%Y%m%dT%H%MZ")"
  img_name="metal3${IMAGE_TYPE}-${IMAGE_OS}-${img_date}-${commit_short}"
fi

export HOSTNAME="${img_name}"

disk-image-create --no-tmpfs -a amd64 -o "${img_name}".qcow2 "${IMAGE_OS}"-"${IMAGE_TYPE}" block-device-efi

echo "${img_name}" > "${REPO_ROOT}/image_name.txt"
