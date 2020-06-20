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
GITHUB_TOKEN="${10}"
export NUM_NODES="${11:-2}"
TESTS_FOR="${12:-integration_test}"

if [ "${NUM_NODES}" == "null" ]
then
  unset NUM_NODES
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


if [ "${DISTRIBUTION}" == "ubuntu" ]; then
  #Must match with run_fetch_logs.sh
  export CONTAINER_RUNTIME="docker"
  export EPHEMERAL_CLUSTER="kind"
else
  export EPHEMERAL_CLUSTER="minikube"
fi

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
  export METAL3REPO="${UPDATED_REPO}"
  export METAL3BRANCH="${UPDATED_BRANCH}"

  # If the target repo and branch are the same as the source repo and branch
  # we're running a master test, that is not for a PR, so we build the image
  # for CAPM3 to verify the process (not BMO due to the build time for BMO image)
  if [[ "${UPDATED_BRANCH}" == "${REPO_BRANCH}" ]] && [[ "${UPDATED_REPO}" == *"${REPO_ORG}/${REPO_NAME}"* ]]; then
    export BAREMETAL_OPERATOR_LOCAL_IMAGE="https://github.com/metal3-io/baremetal-operator.git"
    export CAPM3_LOCAL_IMAGE="https://github.com/metal3-io/cluster-api-provider-metal3.git"
    if [ "${CAPI_VERSION}" == "v1alpha3" ]
    then
      export CAPM3_LOCAL_IMAGE_BRANCH="release-0.3"
    else
      export CAPM3_LOCAL_IMAGE_BRANCH="master"
    fi
  fi

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

elif [[ "${REPO_NAME}" == "project-infra" ]]
then
  export BAREMETAL_OPERATOR_LOCAL_IMAGE="https://github.com/metal3-io/baremetal-operator.git"
  export CAPM3_LOCAL_IMAGE="https://github.com/metal3-io/cluster-api-provider-metal3.git"
  if [ "${CAPI_VERSION}" == "v1alpha3" ]
  then
    export CAPM3_LOCAL_IMAGE_BRANCH="release-0.3"
  else
    export CAPM3_LOCAL_IMAGE_BRANCH="master"
  fi
fi

export GITHUB_TOKEN="${GITHUB_TOKEN}"

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

if [ "${TESTS_FOR}" == "feature_tests" ]
then
  make feature_tests
else
  make
  make test
fi
