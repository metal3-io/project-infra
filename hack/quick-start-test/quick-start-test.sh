#!/usr/bin/env bash

#------------------------------------------------------------------------------
# This script sets up a quick start test environment for Metal3 by
# configuring a virtual lab, bootstrapping a Kind cluster, setting up
# DHCP and image servers, and deploying Ironic and baremetal operators.
#------------------------------------------------------------------------------
set -eux

export QUICK_START_BASE="$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")"

setup() {
    echo "Disk images directory. If disk images are missing, they will be downloaded and prepared."
    setup_disk_images_dir

    echo "Setting up virtual lab..."
    "${QUICK_START_BASE}/setup-virtual-lab.sh"
    # Check if the VM is running
    if ! virsh -c qemu:///system dominfo bmh-vm-01 &> /dev/null; then
        echo "Error: The VM bmh-vm-01 is not running."
        exit 1
    fi

    echo "Bootstrapping Kind cluster..."
    "${QUICK_START_BASE}/setup-bootstrap.sh"
    # Wait for all nodes to be ready
    if ! kubectl wait --for=condition=Ready nodes --all --timeout=300s; then
        exit 1
    fi
    # Wait for cert-manager and webhook to be ready
    wait_for_cert_manager_ready

    echo "Setting up DHCP and image servers..."
    "${QUICK_START_BASE}/start-image-server.sh"
    "${QUICK_START_BASE}/setup-dhcp-server.sh"
    
    echo "Deploying Ironic..."
    kubectl apply -k ironic
    wait_for_ironic_ready

    echo "Deploying Baremetal Operator..."
    kubectl apply -k bmo
    wait_for_bmo_ready
}

create_bmhs() {
    kubectl apply -f "${QUICK_START_BASE}/bml-vm-01.yaml"
    kubectl apply -f "${QUICK_START_BASE}/bml-01.yaml"
    # Wait for BMHs to be provisioned
    wait_for_bml_ready
}

setup_disk_images_dir() {
    DISK_IMAGE_DIR="${QUICK_START_BASE}/disk-images"
    REQUIRED_FILES=(
        "noble-server-cloudimg-amd64.img"
        "CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
        "CENTOS_9_NODE_IMAGE_K8S_v1.34.0.qcow2"
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
    echo "Waiting for cert-manager to be ready... This may take up to 5 minutes."
    if ! kubectl wait --for=condition=Available --timeout=60s deployment/cert-manager -n cert-manager; then
        exit 1
    fi
    if ! kubectl wait --for=condition=Available --timeout=60s deployment/cert-manager-webhook -n cert-manager; then
        exit 1
    fi
    if ! kubectl wait --for=condition=Available --timeout=60s deployment/cert-manager-cainjector -n cert-manager; then
        exit 1
    fi
    if ! kubectl wait --for=condition=Ready --timeout=600s pod -l app.kubernetes.io/name=webhook -n cert-manager; then
        exit 1
    fi
}

wait_for_bmo_ready() {
    echo "Waiting for Baremetal Operator to be ready... This may take up to 5 minutes."
    if ! kubectl wait --for=condition=Available --timeout=300s deployment/baremetal-operator-controller-manager -n baremetal-operator-system; then
        exit 1
    fi
}

wait_for_ironic_ready() {
    echo "Waiting for Ironic to be ready... This may take up to 10 minutes."
    if ! kubectl wait --for=condition=Available --timeout=600s deployment/ironic -n baremetal-operator-system; then
        exit 1
    fi
}

wait_for_bml_ready() {
    echo "Waiting for BareMetalHosts to be provisioned... This may take up to 5 minutes."
    if ! kubectl wait --for=condition=Available --timeout=300s baremetalhosts --all; then
        exit 1
    fi
}

setup
create_bmhs
