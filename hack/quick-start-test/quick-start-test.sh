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

    echo "Setting up DHCP and image servers..."
    "${QUICK_START_BASE}/start-image-server.sh"
}

create_bmhs() {
    kubectl apply -f "${QUICK_START_BASE}/bmc-secret.yaml"
    kubectl apply -f "${QUICK_START_BASE}/bmh-01.yaml"
    # Wait for BMHs to be provisioned
    wait_for_bml_ready
}

setup_disk_images_dir() {
    DISK_IMAGE_DIR="${QUICK_START_BASE}/disk-images"
    REQUIRED_FILES=(
        "noble-server-cloudimg-amd64.img"
        "CENTOS_10_NODE_IMAGE_K8S_v1.34.1.qcow2"
        "CENTOS_10_NODE_IMAGE_K8S_v1.34.1.raw"
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

wait_for_bml_ready() {
    echo "Waiting for BareMetalHosts to be provisioned... This may take up to 12 minutes."
    if ! kubectl wait --for=condition=Available --timeout=720s baremetalhosts --all; then
        exit 1
    fi
}

setup