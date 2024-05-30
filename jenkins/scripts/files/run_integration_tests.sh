#!/usr/bin/env bash

set -eux

VARS_FILE="${1:?}"
export GITHUB_TOKEN="${2:?}"

# shellcheck disable=SC1090
source "${VARS_FILE}"

export CAPI_VERSION
export CAPM3_VERSION
export CAPM3RELEASEBRANCH
export BMORELEASEBRANCH
export IMAGE_OS
export TARGET_NODE_MEMORY
# unsetting NUM_NODES and KUBECTL_SHA256 when it is unbound
# in BML tests it is not passed through vars file
export NUM_NODES="${NUM_NODES:-}"
export KUBECTL_SHA256="${KUBECTL_SHA256:-}"

if [[ "${NUM_NODES}" == "null" ]]; then
    unset NUM_NODES
fi

if [[ "${KUBECTL_SHA256}" == "null" ]]; then
    unset KUBECTL_SHA256
fi

# Since we take care of the repo tested here (to merge the PR), do not update
# the repo in metal3-dev-env 03_launch_mgmt_cluster.sh
export FORCE_REPO_UPDATE=false

if [[ "${IMAGE_OS}" == "ubuntu" ]]; then
    #Must match with run_fetch_logs.sh
    export CONTAINER_RUNTIME="docker"
    export EPHEMERAL_CLUSTER="kind"
else
    export EPHEMERAL_CLUSTER="minikube"
fi

# In the bare metal lab, we have already cloned metal3-dev-env and we run integration tests
# so no need to clone other repos.
if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    cd tested_repo
else
    cd metal3
fi

# See bare metal lab infrastructure documentation:
# https://wiki.nordix.org/pages/viewpage.action?spaceKey=CPI&title=Bare+Metal+Lab
# In the bare metal lab, the external network has vlan id 3
export EXTERNAL_VLAN_ID="3"

make test

