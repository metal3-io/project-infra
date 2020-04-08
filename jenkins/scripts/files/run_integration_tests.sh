#!/bin/bash

set -eux

REPO_ORG="${1:-metal3-io}"
REPO_NAME="${2:-metal3-dev-env}"
REPO_BRANCH="${3:-master}"
UPDATED_REPO="${4:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
UPDATED_BRANCH="${5:-master}"
export CAPI_VERSION="${6:-v1alpha3}"
export IMAGE_OS="${7:-Ubuntu}"
export DEFAULT_HOSTS_MEMORY="${8:-4096}"
DISTRIBUTION="${9:-ubuntu}"

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


if [ "${DISTRIBUTION}" == "ubuntu" ]; then
  export CONTAINER_RUNTIME="docker"
  export EPHEMERAL_CLUSTER="kind"
else
  export EPHEMERAL_CLUSTER="minikube"
fi

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
   METAL3REPO="${UPDATED_REPO}"
   METAL3BRANCH="${UPDATED_BRANCH}"
elif [ "${REPO_NAME}" == "baremetal-operator" ]
then
   export BMOREPO="${UPDATED_REPO}"
   export BMOBRANCH="${UPDATED_BRANCH}"
   export BMOPATH="/home/${USER}/tested_repo"
   export BAREMETAL_OPERATOR_LOCAL_IMAGE="${BMOPATH}"
elif [ "${REPO_NAME}" == "ironic-image" ]
then
   export IRONIC_LOCAL_IMAGE="/home/${USER}/tested_repo"
elif [ "${REPO_NAME}" == "ironic-inspector-image" ]
then
  export IRONIC_INSPECTOR_LOCAL_IMAGE="/home/${USER}/tested_repo"
elif [ "${REPO_NAME}" == "ironic-ipa-downloader" ]
then
  export IPA_DOWNLOADER_LOCAL_IMAGE="/home/${USER}/tested_repo"
elif [[ "${REPO_NAME}" == "cluster-api-provider-"* ]]
then
   export CAPM3REPO="${UPDATED_REPO}"
   export CAPM3BRANCH="${UPDATED_BRANCH}"
   export CAPM3PATH="/home/${USER}/tested_repo"
   export CAPM3_LOCAL_IMAGE="/home/${USER}/tested_repo"
fi

METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
METAL3BRANCH="${METAL3BRANCH:-master}"

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
  pushd tested_repo
else
  git clone "${METAL3REPO}" metal3
  pushd metal3
  git checkout "${METAL3BRANCH}"
fi
make

if [ "${CAPI_VERSION}" == v1alpha1 ]; then
  make test_v1a1
else
  make test
fi

make clean
