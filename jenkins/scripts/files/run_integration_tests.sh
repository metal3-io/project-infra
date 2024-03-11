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
export EPHEMERAL_TEST
export GINKGO_FOCUS
export GINKGO_SKIP
export KEEP_TEST_ENV
# unsetting NUM_NODES and KUBECTL_SHA256 when it is unbound
# in BML tests it is not passed through vars file
export NUM_NODES="${NUM_NODES:-}"
export KUBECTL_SHA256="${KUBECTL_SHA256:-}"
export UPGRADE_FROM_RELEASE
export KUBERNETES_VERSION_UPGRADE_FROM
export KUBERNETES_VERSION_UPGRADE_TO

if [[ "${REPO_NAME}" == "metal3-dev-tools" ]]; then
    export IMAGE_NAME
    export IMAGE_LOCATION
    export KUBERNETES_VERSION
    export KUBECTL_SHA256
fi

if [[ "${CAPM3_VERSION}" == "v1alpha5" ]]; then
    export KUBERNETES_VERSION="v1.23.8"
    export KUBECTL_SHA256="${KUBECTL_SHA256:-4685bfcf732260f72fce58379e812e091557ef1dfc1bc8084226c7891dd6028f}"
fi

if [[ "${GINKGO_FOCUS}" == "k8s-upgrade" ]]; then
    export KUBERNETES_VERSION="${KUBERNETES_VERSION_UPGRADE_TO}"
    export KUBECTL_SHA256="${KUBECTL_SHA256}"
    export FROM_K8S_VERSION="${KUBERNETES_VERSION_UPGRADE_FROM}"
fi

if [[ "${NUM_NODES}" == "null" ]]; then
    unset NUM_NODES
fi

if [[ "${GINKGO_FOCUS}" == "null" ]]; then
    unset GINKGO_FOCUS
fi

if [[ "${GINKGO_SKIP}" == "null" ]]; then
    unset GINKGO_SKIP
fi

if [[ "${EPHEMERAL_TEST}" == "null" ]]; then
    unset EPHEMERAL_TEST
fi

if [[ "${KEEP_TEST_ENV}" == "null" ]]; then
    unset KEEP_TEST_ENV
fi

if [[ "${UPGRADE_FROM_RELEASE}" == "null" ]]; then
    unset UPGRADE_FROM_RELEASE
fi

if [[ "${KUBERNETES_VERSION_UPGRADE_FROM}" == "null" ]]; then
    unset KUBERNETES_VERSION_UPGRADE_FROM
fi

if [[ "${KUBERNETES_VERSION_UPGRADE_TO}" == "null" ]]; then
    unset KUBERNETES_VERSION_UPGRADE_TO
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

if [[ ${BARE_METAL_LAB} == "true" ]]; then
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
    exit 0
fi

# Clone the source repository
cd "/home/${USER}"
git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" tested_repo
cd tested_repo
git checkout "${REPO_BRANCH}"
# If the target and source repos and branches are identical, don't try to merge
if [[ "${UPDATED_REPO}" != *"${REPO_ORG}/${REPO_NAME}"* ]] ||
    [[ "${UPDATED_BRANCH}" != "${REPO_BRANCH}" ]]; then
    git config user.email "test@test.test"
    git config user.name "Test"
    git remote add test "${UPDATED_REPO}"
    git fetch test
    # if triggered from prow we cannot get the ghprbAuthorRepoGitUrl then we pull the PR
    git fetch origin "pull/${PR_ID:-0}/head:${UPDATED_BRANCH}-branch" || true
    # Merging the PR with the target branch
    git merge "${UPDATED_BRANCH}" || exit
fi
cd "/home/${USER}"

if [[ ("${TESTS_FOR}" != "e2e_tests" && "${REPO_NAME}" == "metal3-dev-env") ||
    ("${TESTS_FOR}" == "e2e_tests" && "${REPO_NAME}" == "cluster-api-provider-metal3") ]] \
    ; then
    # If we are testing ansible test from metal3-dev-env or e2e from capm3,
    # it will already be cloned to tested_repo
    pushd tested_repo
elif [[ "${TESTS_FOR}" == "e2e_tests" ]]; then
    # only if the test is e2e clone capm3 and run the test from there
    git clone "${CAPM3REPO}" metal3
    pushd metal3
    git checkout "${CAPM3BRANCH}"
else
    # if not e2e test clone dev-env since ansible integration tests are
    # triggered from there
    git clone "${METAL3REPO}" metal3
    pushd metal3
    git checkout "${METAL3BRANCH}"
fi

if [[ "${TESTS_FOR}" == "e2e_tests" ]]; then
    make test-e2e
else
    make
    make test
fi
