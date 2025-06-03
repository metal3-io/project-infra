#!/usr/bin/env bash

# Set variables based on what repo is being tested.
# All of them are tested using metal3-dev-env, but we only build images for the
# currently tested repo (by setting *_LOCAL_IMAGE vars).

if [[ "${REPO_NAME}" == "metal3-dev-env" ]]; then
    export METAL3REPO="${UPDATED_REPO}"
    export METAL3BRANCH="${UPDATED_BRANCH}"
    export M3_DEV_ENV_PATH="${HOME}/tested_repo"

    # If the target repo and branch are the same as the source repo and branch
    # we're running a periodic test, that is not for a PR, so we build the CAPM3, BMO and IPAM images)

    if [[ "${UPDATED_BRANCH}" == "${REPO_BRANCH}" ]] && [[ "${UPDATED_REPO}" == *"${REPO_ORG}/${REPO_NAME}"* ]]; then
        export BUILD_BMO_LOCALLY="true"
        export BUILD_CAPM3_LOCALLY="true"
        export BUILD_IPAM_LOCALLY="true"
    fi

elif [[ "${REPO_NAME}" == "baremetal-operator" ]]; then
    export BMOREPO="${UPDATED_REPO}"
    export BMOBRANCH="${UPDATED_BRANCH}"
    export BMOPATH="/home/${USER}/tested_repo"
    export BUILD_BMO_LOCALLY="true"

elif [[ "${REPO_NAME}" == "ip-address-manager" ]]; then
    export IPAMREPO="${UPDATED_REPO}"
    export IPAMBRANCH="${UPDATED_BRANCH}"
    export IPAMPATH="/home/${USER}/tested_repo"
    export BUILD_IPAM_LOCALLY="true"

elif [[ "${REPO_NAME}" == "ironic-image" ]]; then
    export IRONIC_LOCAL_IMAGE="/home/${USER}/tested_repo"
    # Build/test the sushy-tools/vbmc images, since they are defined in this repo
    export SUSHY_TOOLS_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE}/resources/sushy-tools"
    export VBMC_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE}/resources/vbmc"

elif [[ "${REPO_NAME}" == "mariadb-image" ]]; then
    export MARIADB_LOCAL_IMAGE="/home/${USER}/tested_repo"

elif [[ "${REPO_NAME}" == "ironic-ipa-downloader" ]]; then
    export IPA_DOWNLOADER_LOCAL_IMAGE="/home/${USER}/tested_repo"

elif [[ "${REPO_NAME}" == "cluster-api-provider-metal3" ]]; then
    export CAPM3REPO="${UPDATED_REPO}"
    export CAPM3BRANCH="${UPDATED_BRANCH}"
    export CAPM3PATH="/home/${USER}/tested_repo"
    export BUILD_CAPM3_LOCALLY="true"
fi

export GITHUB_TOKEN

# Ansible colors
export ANSIBLE_FORCE_COLOR=true
# Make 'changed' tasks the same color as 'succeeded' tasks in Jenkins output
export ANSIBLE_COLOR_CHANGED="green"

METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
METAL3BRANCH="${METAL3BRANCH:-main}"
CAPM3REPO="${CAPM3REPO:-https://github.com/metal3-io/cluster-api-provider-metal3}"
CAPM3BRANCH="${CAPM3BRANCH:-${CAPM3RELEASEBRANCH}}"

# Container image registry value to override the default value in m3-dev-env
export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"registry.nordix.org/quay-io-proxy"}
export DOCKER_HUB_PROXY=${DOCKER_HUB_PROXY:-"registry.nordix.org/docker-hub-proxy"}

# Proxy IPA's base URI value to override the default value in m3-dev-env
export IPA_BASEURI="https://artifactory.nordix.org/artifactory/openstack-remote-cache/ironic-python-agent/dib"
