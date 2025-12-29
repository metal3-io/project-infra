#!/usr/bin/env bash

set -eux

# shellcheck disable=SC1091
. lib/vars.sh

USER="$(whoami)"

# Clone Baremetal Operator repo
git clone https://github.com/metal3-io/baremetal-operator.git "${BMOPATH}" || true
git clone https://github.com/metal3-io/cluster-api-provider-metal3.git "${CAPM3PATH}" || true
git clone https://github.com/metal3-io/ip-address-manager.git "${IPAMPATH}" || true
git clone https://github.com/metal3-io/ironic-standalone-operator.git "${IRSOPATH}" || true

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

    kubectl create secret tls ironic-cert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_KEY_FILE}" --cert="${IRONIC_CERT_FILE}"
    kubectl create secret tls ironic-cacert -n "${IRONIC_NAMESPACE}" --key="${IRONIC_CAKEY_FILE}" --cert="${IRONIC_CACERT_FILE}"

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
        # FIXME(dtantsur): remove this when Ironic objects are collected in the CI
        kubectl get -n "${IRONIC_NAMESPACE}" -o yaml ironic/ironic
        exit 1
    fi
}

launch_ironic()
{
    pushd "${BMOPATH}"
    # Update Configmap parameters with correct urls
    # Variable names inserted into the configmap might have different
    # naming conventions than the dev-env e.g. PROVISIONING_IP and CIDR are
    # called PROVISIONER_IP and CIDR in dev-env
    cat << EOF | sudo tee "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env"
HTTP_PORT=6180
PROVISIONING_IP=${IRONIC_HOST_IP}
PROVISIONING_CIDR=24
PROVISIONING_INTERFACE=ironicendpoint
DHCP_RANGE=172.22.0.10,172.22.0.100
DEPLOY_KERNEL_URL=http://${IRONIC_HOST_IP}:6180/images/ironic-python-agent.kernel
DEPLOY_RAMDISK_URL=http://${IRONIC_HOST_IP}:6180/images/ironic-python-agent.initramfs
IRONIC_ENDPOINT=https://${IRONIC_HOST_IP}:6385/v1/
IRONIC_INSPECTOR_ENDPOINT=https://${IRONIC_HOST_IP}:5050/v1/
CACHEURL=http://172.22.0.1/images
RESTART_CONTAINER_CERTIFICATE_UPDATED="true"
IRONIC_RAMDISK_SSH_KEY=ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0NpYlHF/Hobhx7raalkw6lzgExxJvhYCxlc6/8Ju2xH/TDqOXnKa/VaZDWBjOHJmP+NVgBj+vnUsA/CI+PVdCd1QkMMle4BBSfWiPrbVF+cYeUjx9P1kBQLPZ70n9pi291hqW8TwF3ZrYIgr3arCPmBrYQW2dNChhaLFe57DOIgMClmFirsl+pwNPiqudEzfmQd8QbP8qnGxzT+LR3yc6W1F4ismWpMWU0gKSy6EdPh37D0eq5xW8KK5h9jV22Y1spEJrYpmyNj/Ks5Z7d7h/LWLpmeUMNh2+9+UAHM8eemeCBT4ICKuBUK0qMfc7VpeqNmzwKsvyOE1/d1v/gQn7GtMr7oUazGpjlGOrafblIXQxpCzDayKmWNca1P6/SR4Qz2YcgkL0o4VwkyfP/MxvaNUteNj3ZqOjJrVDfOIwQEcMC6k1p1Gx3CLpalg6OQ/eXfOOZSTFvjrH3EU2cKjLRhbXjKP/bt/eaIk7m/DdUUs7kE7HD88mSxf/v9CYURM= metal3ci@eselda13u31s02
IRONIC_USE_MARIADB=false
USE_IRONIC_INSPECTOR=false
IPA_BASEURI=http://172.22.0.1/images
IPA_BRANCH=master
IPA_FLAVOR=centos9
IRONIC_KERNEL_PARAMS=console=ttyS0
DHCP_IGNORE=tag:!known
DHCP_HOSTS=b4:b5:2f:6d:89:d8;80:c1:6e:7a:5a:a8;6c:3b:e5:b5:03:c8;10:60:4b:b4:be:00;b4:b5:2f:6f:01:40;6c:3b:e5:b5:03:c8;40:A6:B7:C9:73:93;80:c1:6e:7a:e8:10;40:a6:b7:c9:75:33;5c:25:73:8c:72:dc;5c:25:73:8c:72:dd;5c:25:73:8c:71:c4;5c:25:73:8c:71:c5
EOF

    # Copy the generated configmap for ironic deployment
    cp "${IRONIC_DATA_DIR}/ironic_bmo_configmap.env" "${BMOPATH}/ironic-deployment/components/keepalived/ironic_bmo_configmap.env"

    # Deploy Ironic using deploy.sh script
    "${BMOPATH}/tools/deploy.sh" -i -k -t
    popd
}

# Start management cluster
start_management_cluster
kubectl create namespace metal3

patch_clusterctl
patch_ipam

# launch CAPM3, CAPI and IPAM
clusterctl init --core cluster-api:"${CAPIRELEASE}" --bootstrap kubeadm:"${CAPIRELEASE}" \
      --control-plane kubeadm:"${CAPIRELEASE}" --infrastructure=metal3:"${CAPM3RELEASE}"  -v5 --ipam=metal3:"${IPAMRELEASE}"

launch_baremetal_operator
launch_ironic_standalone_operator
launch_ironic_via_irso
