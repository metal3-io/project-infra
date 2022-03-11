#!/bin/bash

set -eux

VARS_FILE="${1}"
GITHUB_TOKEN="${2}"

source "${VARS_FILE}"

export CAPI_VERSION
export CAPM3_VERSION
export IMAGE_OS
export DEFAULT_HOSTS_MEMORY
export NUM_NODES
export UPGRADE_TEST
export EPHEMERAL_TEST

if [ "${REPO_NAME}" == "metal3-dev-tools" ]
then
  export IMAGE_NAME
  export IMAGE_LOCATION
  export KUBERNETES_VERSION
fi

if [ "${CAPM3_VERSION}" == "v1alpha4" ]
then
  export KUBERNETES_VERSION="v1.21.2"
fi

if [ "${NUM_NODES}" == "null" ]
then
  unset NUM_NODES
fi

if [ "${UPGRADE_TEST}" == "null" ]
then
  unset UPGRADE_TEST
fi

if [ "${EPHEMERAL_TEST}" == "null" ]
then
  unset EPHEMERAL_TEST
fi

# Since we take care of the repo tested here (to merge the PR), do not update
# the repo in metal3-dev-env 03_launch_mgmt_cluster.sh
export FORCE_REPO_UPDATE=false

# Clone the source repository
cd "/home/${USER}"
git clone "https://github.com/${REPO_ORG}/${REPO_NAME}.git" tested_repo
cd tested_repo
git checkout "${REPO_BRANCH}"
# If the target and source repos and branches are identical, don't try to merge
if [[ "${UPDATED_REPO}" != *"${REPO_ORG}/${REPO_NAME}"* ]] || \
  [[ "${UPDATED_BRANCH}" != "${REPO_BRANCH}" ]]
then
  git config user.email "test@test.test"
  git config user.name "Test"
  git remote add test "${UPDATED_REPO}"
  git fetch test
  # Merging the PR with the target branch
  git merge "${UPDATED_BRANCH}" || exit
fi
cd "/home/${USER}"


if [ "${IMAGE_OS}" == "ubuntu" ]; then
  #Must match with run_fetch_logs.sh
  export CONTAINER_RUNTIME="docker"
  export EPHEMERAL_CLUSTER="kind"
else
  export EPHEMERAL_CLUSTER="minikube"
fi

# If we are testing metal3-dev-env, it will already be cloned to tested_repo
if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
  pushd tested_repo
else
  git clone "${METAL3REPO}" metal3
  pushd metal3
  git checkout "${METAL3BRANCH}"
fi

if [[ ${BARE_METAL_LAB} == "true" ]]
then
  # See bare metal lab infrastructure documentation:
  # https://wiki.nordix.org/pages/viewpage.action?spaceKey=CPI&title=Bare+Metal+Lab
  # In the bare metal lab, the external network has vlan id 3
  export EXTERNAL_VLAN_ID="3"
  make test
  exit 0
fi

if [[ "${TESTS_FOR}" == "feature_tests_upgrade"* ]]
then
  export NODE_DRAIN_TIMEOUT="300s"
  make "${TESTS_FOR}"
elif [[ "${TESTS_FOR}" == "feature_tests_ubuntu" || "${TESTS_FOR}" == "feature_tests_centos" ]]
then
  make feature_tests
elif [[ "${TESTS_FOR}" == "e2e_tests" ]]
then
  pushd "${CAPM3PATH}"
  make test-e2e
  popd
else
  make
  make test
fi
