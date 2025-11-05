#!/usr/bin/env bash

#------------------------------------------------------------------------------
# This script sets up a quick start test environment for Metal3 by
# configuring a virtual lab, bootstrapping a Kind cluster, setting up
# DHCP and image servers, and deploying Ironic and baremetal operators.
#------------------------------------------------------------------------------
set -eux

export QUICK_START_BASE=${QUICK_START_BASE:="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"}

setup() {
    echo "Disk images directory. If disk images are missing, they will be downloaded and prepared."
    setup_disk_images_dir

    echo "Setting up virtual lab..."
    "${QUICK_START_BASE}/setup-virtual-lab.sh"

    echo "Bootstrapping Kind cluster..."
    "${QUICK_START_BASE}/setup-bootstrap.sh"
    wait_for_nodes_ready
    wait_for_cert_manager_ready

    echo "Setting up DHCP and image servers..."
    "${QUICK_START_BASE}/start-image-server.sh"
    "${QUICK_START_BASE}/setup-dhcp-server.sh"

    IRONIC_USERNAME="$(uuidgen)"
    IRONIC_PASSWORD="$(uuidgen)"

    # These must be exported so that envsubst can pick them up below
    export IRONIC_USERNAME
    export IRONIC_PASSWORD

    echo "${IRONIC_USERNAME}" > "${QUICK_START_BASE}/bmo/ironic-username"
    echo "${IRONIC_PASSWORD}" > "${QUICK_START_BASE}/bmo/ironic-password"

    echo "${IRONIC_USERNAME}" > "${QUICK_START_BASE}/irso/ironic-username"
    echo "${IRONIC_PASSWORD}" > "${QUICK_START_BASE}/irso/ironic-password"

    # Replace in the username and password in bml-vm-01.yaml
    sed -i "s/username: .*/username: ${IRONIC_USERNAME}/" ${QUICK_START_BASE}/bml-01.yaml
    sed -i "s/password: .*/password: ${IRONIC_PASSWORD}/" ${QUICK_START_BASE}/bml-01.yaml

    echo "Deploying IrSO..."
    # This is deploying a patch where the IPA_BASEURI are set to the local image server.
    # This could be replaced with just kubectl apply -f https://github.com/metal3-io/ironic-standalone-operator/releases/latest/download/install.yaml
    kubectl apply -k irso
    wait_for_resource Available deployment ironic-standalone-operator-controller-manager ironic-standalone-operator-system 300

    kubectl create namespace baremetal-operator-system
    echo "Deploying Baremetal Operator..."
    kubectl apply -k bmo
    wait_for_resource Available deployment baremetal-operator-controller-manager baremetal-operator-system 300

    # This could be replaced with just kubectl apply -f https://raw.githubusercontent.com/metal3-io/baremetal-operator/refs/heads/main/test/e2e/data/ironic-standalone-operator/ironic/base/ironic.yaml
    kubectl apply -f ${QUICK_START_BASE}/irso/ironic.yaml
    wait_for_resource Available deployment ironic-service baremetal-operator-system 300
}

create_bmhs() {
    kubectl apply -f "${QUICK_START_BASE}/bml-01.yaml"
    kubectl apply -f "${QUICK_START_BASE}/bml-vm-01.yaml"
    # Wait for BMHs to be provisioned
    wait_for_bml_ready
}

setup_disk_images_dir() {
    DISK_IMAGE_DIR="${QUICK_START_BASE}/disk-images"
    REQUIRED_FILES=(
        "noble-server-cloudimg-amd64.img"
        "CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
        "CENTOS_9_NODE_IMAGE_K8S_v1.34.0.qcow2"
        "ipa-centos9-master.tar.gz"
    )

    missing_files=0
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "${DISK_IMAGE_DIR}/${file}" ]; then
            missing_files=1
            break
        fi
    done

    if [ "$missing_files" -eq 1 ]; then
        rm -r ${DISK_IMAGE_DIR} || true
        echo "Setting up disk images directory..."
        "${QUICK_START_BASE}/setup-image-server-dir.sh"
    else
        echo "All required disk images are present."
    fi
}

wait_for_cert_manager_ready() {
    echo "Waiting for cert-manager to be ready... This may take up to 2 minutes."
    if ! kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager -n cert-manager; then
        exit 1
    fi
    if ! kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager-webhook -n cert-manager; then
        exit 1
    fi
    if ! kubectl wait --for=condition=Available --timeout=120s deployment/cert-manager-cainjector -n cert-manager; then
        exit 1
    fi
}

wait_for_nodes_ready() {
    echo "Waiting for all nodes to be ready... This may take up to 5 minutes."
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s; then
        exit 1
    fi
}

wait_for_resource() {
    status="$1"
    resource="$2"
    name="$3"
    namespace="$4"
    timeout="$5"
    MAX_RETRIES=5
    RETRY_DELAY=2

    echo "Waiting for ${resource} ${name} to be ready... This may take up to ${timeout} seconds."
    for ((i=1; i<=MAX_RETRIES; i++)); do
        if ! kubectl wait --for=condition=${status} --timeout=${timeout}s ${resource}/${name} -n ${namespace}; then
            if [ $i -eq MAX_RETRIES ]; then
                exit 1
            else
                echo "${resource} ${name} not ready yet. Attempt $i of ${MAX_RETRIES}. Retrying..."
                sleep ${RETRY_DELAY}
            fi
        fi
    done
}

wait_for_bml_ready() {
    echo "Waiting for BareMetalHosts to be provisioned... This may take up to 12 minutes."
    if ! kubectl wait --for=condition=Available --timeout=720s baremetalhosts --all; then
        exit 1
    fi
}

setup
create_bmhs
