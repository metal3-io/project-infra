#!/bin/bash

set -eux

export CONTAINER_RUNTIME="docker"

REPO_ORG="${1:-metal3-io}"
REPO_NAME="${2:-metal3-dev-env}"
REPO_BRANCH="${3:-master}"
UPDATED_REPO="${4:-https://github.com/${REPO_ORG}/${REPO_NAME}.git}"
export CAPI_VERSION="${5:-v1alpha2}"
export IMAGE_OS="${6:-Ubuntu}"
export DEFAULT_HOSTS_MEMORY="${7:-4096}"

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
   METAL3REPO="${UPDATED_REPO}"
   METAL3BRANCH="${REPO_BRANCH}"
elif [ "${REPO_NAME}" == "baremetal-operator" ]
then
   export BMOREPO="${UPDATED_REPO}"
   export BMOBRANCH="${REPO_BRANCH}"
   export BAREMETAL_OPERATOR_LOCAL_IMAGE="${UPDATED_REPO}"
   export BAREMETAL_OPERATOR_LOCAL_IMAGE_BRANCH="${REPO_BRANCH}"
elif [ "${REPO_NAME}" == "ironic-image" ]
then
   export IRONIC_LOCAL_IMAGE="${UPDATED_REPO}"
   export IRONIC_LOCAL_IMAGE_BRANCH="${REPO_BRANCH}"
elif [ "${REPO_NAME}" == "ironic-inspector-image" ]
then
  export IRONIC_INSPECTOR_LOCAL_IMAGE="${UPDATED_REPO}"
  export IRONIC_INSPECTOR_LOCAL_IMAGE_BRANCH="${REPO_BRANCH}"
elif [ "${REPO_NAME}" == "ironic-ipa-downloader" ]
then
  export IPA_DOWNLOADER_LOCAL_IMAGE="${UPDATED_REPO}"
  export IPA_DOWNLOADER_LOCAL_IMAGE_BRANCH="${REPO_BRANCH}"
elif [ "${REPO_NAME}" == "cluster-api-provider-baremetal" ]
then
   export CAPBMREPO="${UPDATED_REPO}"
   export CAPBMBRANCH="${REPO_BRANCH}"
   export CAPBM_LOCAL_IMAGE="${UPDATED_REPO}"
   export CAPBM_LOCAL_IMAGE_BRANCH="${REPO_BRANCH}"
fi

METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
METAL3BRANCH="${METAL3BRANCH:-master}"

git clone "${METAL3REPO}" metal3
pushd metal3
git checkout "${METAL3BRANCH}"
make

if [ "${CAPI_VERSION}" == v1alpha1 ]; then
  make test
elif [ "${CAPI_VERSION}" == v1alpha2 ]; then
  make test_v1a2
fi

make clean
