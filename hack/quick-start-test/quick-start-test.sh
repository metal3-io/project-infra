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

    echo "Setting up DHCP and image servers..."
    "${QUICK_START_BASE}/start-image-server.sh"

    echo "Bootstrapping Kind cluster..."
    "${QUICK_START_BASE}/setup-bootstrap.sh"
    if ! kubectl -n baremetal-operator-system wait --for=condition=Available --timeout=300s deployment --all; then
        exit 1
    fi
}

create_bmhs() {
    kubectl apply -f "${QUICK_START_BASE}/bmc-secret.yaml"
    kubectl apply -f "${QUICK_START_BASE}/bmh-01.yaml"
    # Wait for BMHs to be available
    if ! kubectl wait --for=jsonpath='{.status.provisioning.state}'=available --timeout=600s bmh --all; then
        echo "ERROR: One or more BMHs failed to reach 'available' state within timeout."
        exit 1
    fi
}

scenario_2() {
    echo "Running Scenario 2: ..."
    # "clusterctl init --infrastructure metal3 --ipam=metal3" has already been run.
    # Define env variables
    source "${QUICK_START_BASE}/capm3-vars.sh"

    # Render and apply manifests
    clusterctl generate cluster test-cluster --control-plane-machine-count 1 --worker-machine-count 0 | kubectl apply -f -
    
    # Wait for bml-vm-01 to be provisioned
    if ! kubectl wait --for=jsonpath='{.status.provisioning.state}'=provisioned --timeout=1800s bmh bml-vm-01; then
        echo "ERROR: bml-vm-01 failed to reach 'provisioned' state within timeout."
        exit 1
    fi

    # Get kubeconfig for the workload cluster and install CNI
    clusterctl get kubeconfig test-cluster > test-cluster-kubeconfig.yaml
    kubectl --kubeconfig=test-cluster-kubeconfig.yaml apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.0/manifests/calico.yaml

    # Wait for the control plane machine to be ready
    if ! kubectl wait --for=condition=Ready --timeout=600s machine --all; then
        echo "ERROR: Machine failed to reach 'Ready' state within timeout."
        exit 1
    fi
}

setup_disk_images_dir() {
    DISK_IMAGE_DIR="${QUICK_START_BASE}/disk-images"
    REQUIRED_FILES=(
        "jammy-server-cloudimg-amd64.img"
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

setup
create_bmhs
scenario_2