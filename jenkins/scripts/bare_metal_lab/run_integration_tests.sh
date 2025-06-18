#!/usr/bin/env bash

set -eux

export GITHUB_TOKEN="${1:?}"

export CAPI_VERSION
export CAPM3_VERSION
export CAPM3RELEASEBRANCH
export BMORELEASEBRANCH
export IMAGE_OS
export TARGET_NODE_MEMORY
# unsetting NUM_NODES when it is unbound
# in BML tests it is not passed through vars file
export NUM_NODES="${NUM_NODES:-}"

if [[ "${NUM_NODES}" == "null" ]]; then
    unset NUM_NODES
fi

IMAGE_NAME="UBUNTU_24.04_NODE_IMAGE_K8S_v1.33.0.qcow2"
export IMAGE_NAME

# Since we take care of the repo tested here (to merge the PR), do not update
# the repo in metal3-dev-env 03_launch_mgmt_cluster.sh
export FORCE_REPO_UPDATE=false

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    #Must match with fetch_logs.sh
    export CONTAINER_RUNTIME="docker"
fi
export EPHEMERAL_CLUSTER="minikube"

# In the bare metal lab, we have already cloned metal3-dev-env and we run integration tests
# so no need to clone other repos.
if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    cd "${HOME}/tested_repo"
else
    cd "${HOME}/metal3"
fi

# See bare metal lab infrastructure documentation:
# https://wiki.nordix.org/pages/viewpage.action?spaceKey=CPI&title=Bare+Metal+Lab
# In the bare metal lab, the external network has vlan id 3
export EXTERNAL_VLAN_ID="3"

make test
