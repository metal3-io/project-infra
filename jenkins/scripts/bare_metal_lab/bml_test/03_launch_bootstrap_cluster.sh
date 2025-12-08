#!/usr/bin/env bash

set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

set -eux

USER="$(whoami)"
export PATH=/usr/local/go/bin:$PATH

# Configure git for slow networks
# if network goes down  to less than 0.5 Mbps for 120 seconds, git will abort
git config --global http.lowSpeedLimit 62500
git config --global http.lowSpeedTime 120
git config --global http.postBuffer 157286400

# Clone repositories with retry logic for slow networks
clone_with_retry() {
    local repo_url=$1
    local dest_path=$2
    local max_attempts=5
    local attempt=1
    local wait_time=1

    # Skip if already cloned
    if [[ -d "${dest_path}/.git" ]]; then
        echo "Repository already exists at ${dest_path}, skipping clone"
        return 0
    fi

    while [[ ${attempt} -le ${max_attempts} ]]; do
        echo "Attempt ${attempt}/${max_attempts}: Cloning ${repo_url}..."
        if git clone --depth 1 --single-branch "${repo_url}" "${dest_path}"; then
            echo "Successfully cloned ${repo_url}"
            return 0
        else
            echo "Clone attempt ${attempt} failed"
            if [[ ${attempt} -lt ${max_attempts} ]]; then
                echo "Waiting ${wait_time} seconds before retry..."
                sleep ${wait_time}
                wait_time=$((wait_time * 2))  # Exponential backoff
            fi
            attempt=$((attempt + 1))
        fi
    done

    echo "Failed to clone ${repo_url} after ${max_attempts} attempts"
    return 1
}

# Clone Baremetal repos
clone_with_retry "https://github.com/metal3-io/baremetal-operator.git" "${BMOPATH}"
clone_with_retry "https://github.com/metal3-io/cluster-api-provider-metal3.git" "${CAPM3PATH}"
clone_with_retry "https://github.com/metal3-io/ip-address-manager.git" "${IPAMPATH}"
clone_with_retry "https://github.com/metal3-io/ironic-standalone-operator.git" "${IRSOPATH}"

# Update the clusterctl deployment files to use local repositories
#
patch_clusterctl()
{
    pushd "${CAPM3PATH}"

    mkdir -p "${CAPI_CONFIG_DIR}"
    cat << EOF >> "${CAPI_CONFIG_DIR}"/clusterctl.yaml
providers:
- name: metal3
  url: https://github.com/metal3-io/ip-address-manager/releases/${IPAMRELEASE}/ipam-components.yaml
  type: IPAMProvider
EOF

    # At this point the images variables have been updated with update_images
    # Reflect the change in components files
    export MANIFEST_IMG="${CONTAINER_REGISTRY}/metal3-io/cluster-api-provider-metal3"
    export MANIFEST_TAG="main"
    make set-manifest-image

    make release-manifests

    rm -rf "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    mkdir -p "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    cp out/*.yaml "${CAPI_CONFIG_DIR}"/overrides/infrastructure-metal3/"${CAPM3RELEASE}"
    popd
}

patch_ipam()
{
    pushd "${IPAMPATH}"

    export MANIFEST_IMG="${CONTAINER_REGISTRY}/metal3-io/ip-address-manager"
    export MANIFEST_TAG="main"
    make set-manifest-image

    make release-manifests
    rm -rf "${CAPI_CONFIG_DIR}"/overrides/ipam-metal3/"${IPAMRELEASE}"
    mkdir -p "${CAPI_CONFIG_DIR}"/overrides/ipam-metal3/"${IPAMRELEASE}"
    cp out/*.yaml "${CAPI_CONFIG_DIR}"/overrides/ipam-metal3/"${IPAMRELEASE}"
    popd
}

#
# Create a management cluster
#
start_management_cluster()
{
    local minikube_error

    while /bin/true; do
        minikube_error=0
        sudo su -l -c 'minikube start' "${USER}" || minikube_error=1
        if [[ "${minikube_error}" -eq 0 ]]; then
            break
        fi
    done

    sudo su -l -c "minikube ssh -- sudo brctl addbr ironicendpoint" "${USER}"
    sudo su -l -c "minikube ssh -- sudo ip link set ironicendpoint up" "${USER}"
    sudo su -l -c "minikube ssh -- sudo brctl addif ironicendpoint eth2" "${USER}"
    sudo su -l -c "minikube ssh -- sudo ip addr add 172.22.0.9/24 dev ironicendpoint" "${USER}"

}


launch_baremetal_operator()
{
    pushd "${BMOPATH}"

    # Update Configmap parameters with correct urls
    cat << EOF | sudo tee "${BMOPATH}/config/default/ironic.env"
DEPLOY_KERNEL_URL=http://${IRONIC_HOST_IP}:6180/images/ironic-python-agent.kernel
DEPLOY_RAMDISK_URL=http://${IRONIC_HOST_IP}:6180/images/ironic-python-agent.initramfs
IRONIC_ENDPOINT=https://${IRONIC_HOST_IP}:6385/v1/
IRONIC_INSPECTOR_ENDPOINT=https://${IRONIC_HOST_IP}:5050/v1/
EOF
    export MANIFEST_IMG="${CONTAINER_REGISTRY}/metal3-io/baremetal-operator"
    export MANIFEST_TAG="main"
    make set-manifest-image-bmo
    # Deploy BMO using deploy.sh script
    "${BMOPATH}/tools/deploy.sh" -b -k -t

    popd
}

launch_ironic_standalone_operator()
{
    # shellcheck disable=SC2311
    echo 'IPA_BASEURI=http://172.22.0.1/images' > "${IRSOPATH}/config/manager/manager.env"
    make -C "${IRSOPATH}" install deploy IMG="${IRSO_IMAGE:-"${CONTAINER_REGISTRY}/metal3-io/ironic-standalone-operator:${IRSO_TAG}"}"
    kubectl wait --for=condition=Available --timeout=60s \
        -n ironic-standalone-operator-system deployment/ironic-standalone-operator-controller-manager
}

launch_ironic_via_irso()
{

    kubectl create secret generic ironic-auth -n "${IRONIC_NAMESPACE}" \
        --from-file=username="${IRONIC_AUTH_DIR}ironic-username"  \
        --from-file=password="${IRONIC_AUTH_DIR}ironic-password"

    local ironic="${IRONIC_DATA_DIR}/ironic.yaml"
    cat > "${ironic}" <<EOF
---
apiVersion: ironic.metal3.io/v1alpha1
kind: Ironic
metadata:
  name: ironic
  namespace: "${IRONIC_NAMESPACE}"
spec:
  apiCredentialsName: ironic-auth
  images:
    deployRamdiskBranch: "master"
    deployRamdiskDownloader: "${CONTAINER_REGISTRY}/metal3-io/ironic-ipa-downloader"
    ironic: "${CONTAINER_REGISTRY}/metal3-io/ironic:release-33.0"
    keepalived: "${CONTAINER_REGISTRY}/metal3-io/keepalived:release-0.9"
  version: "${IRSO_IRONIC_VERSION}"
  networking:
    dhcp:
      rangeBegin: "172.22.0.10"
      rangeEnd: "172.22.0.100"
      networkCIDR: "172.22.0.0/24"
    interface: "ironicendpoint"
    ipAddress: "172.22.0.2"
    ipAddressManager: keepalived
  deployRamdisk:
    sshKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0NpYlHF/Hobhx7raalkw6lzgExxJvhYCxlc6/8Ju2xH/TDqOXnKa/VaZDWBjOHJmP+NVgBj+vnUsA/CI+PVdCd1QkMMle4BBSfWiPrbVF+cYeUjx9P1kBQLPZ70n9pi291hqW8TwF3ZrYIgr3arCPmBrYQW2dNChhaLFe57DOIgMClmFirsl+pwNPiqudEzfmQd8QbP8qnGxzT+LR3yc6W1F4ismWpMWU0gKSy6EdPh37D0eq5xW8KK5h9jV22Y1spEJrYpmyNj/Ks5Z7d7h/LWLpmeUMNh2+9+UAHM8eemeCBT4ICKuBUK0qMfc7VpeqNmzwKsvyOE1/d1v/gQn7GtMr7oUazGpjlGOrafblIXQxpCzDayKmWNca1P6/SR4Qz2YcgkL0o4VwkyfP/MxvaNUteNj3ZqOjJrVDfOIwQEcMC6k1p1Gx3CLpalg6OQ/eXfOOZSTFvjrH3EU2cKjLRhbXjKP/bt/eaIk7m/DdUUs7kE7HD88mSxf/v9CYURM= metal3ci@eselda13u31s02"
  tls:
    certificateName: ironic-cert
EOF

    # NOTE(dtantsur): the webhook may not be ready immediately, retry if needed
    while ! kubectl create -f "${ironic}"; do
        sleep 3
    done

    if ! kubectl wait --for=condition=Ready --timeout="${IRONIC_ROLLOUT_WAIT}m" -n "${IRONIC_NAMESPACE}" ironic/ironic; then
        kubectl get -n "${IRONIC_NAMESPACE}" -o yaml ironic/ironic
        exit 1
    fi
}

# Start management cluster
start_management_cluster

# Preload images into minikube
"${SCRIPTDIR}"/preload_images_minikube.sh
kubectl create namespace metal3

kubectl create namespace "${IRONIC_NAMESPACE}"

kubectl create secret tls ironic-cert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_KEY_FILE}" --cert="${IRONIC_CERT_FILE}"
kubectl create secret tls ironic-cacert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_CAKEY_FILE}" --cert="${IRONIC_CACERT_FILE}"

patch_clusterctl
patch_ipam

# launch CAPM3, CAPI and IPAM
clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
      --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5 --ipam=metal3:"${IPAMRELEASE}"

launch_baremetal_operator
launch_ironic_standalone_operator
launch_ironic_via_irso
