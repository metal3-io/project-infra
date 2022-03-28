# Set variables based on what repo is being tested.
# All of them are tested using metal3-dev-env, but we only build images for the
# currently tested repo (by setting *_LOCAL_IMAGE vars).

if [ "${REPO_NAME}" == "metal3-dev-env" ]
then
  export METAL3REPO="${UPDATED_REPO}"
  export METAL3BRANCH="${UPDATED_BRANCH}"

  # If the target repo and branch are the same as the source repo and branch
  # we're running a main test, that is not for a PR, so we build the image
  # for CAPM3 to verify the process (not BMO due to the build time for BMO image)

  if [[ "${UPDATED_BRANCH}" == "${REPO_BRANCH}" ]] && [[ "${UPDATED_REPO}" == *"${REPO_ORG}/${REPO_NAME}"* ]]; then
    export BAREMETAL_OPERATOR_LOCAL_IMAGE="https://github.com/metal3-io/baremetal-operator.git"
    export CAPM3_LOCAL_IMAGE="https://github.com/metal3-io/cluster-api-provider-metal3.git"
    if [ "${CAPM3_VERSION}" == "v1alpha4" ]
    then
      export CAPM3_LOCAL_IMAGE_BRANCH="release-0.4"
    elif [ "${CAPM3_VERSION}" == "v1alpha5" ]
    then
      export CAPM3_LOCAL_IMAGE_BRANCH="release-0.5"
    else
      export CAPM3_LOCAL_IMAGE_BRANCH="main"
    fi
  fi

elif [ "${REPO_NAME}" == "baremetal-operator" ]
then
  export BMOREPO="${UPDATED_REPO}"
  export BMOBRANCH="${UPDATED_BRANCH}"
  export BMOPATH="/home/${USER}/tested_repo"
  export BAREMETAL_OPERATOR_LOCAL_IMAGE="${BMOPATH}"
  export IRONIC_KEEPALIVED_LOCAL_IMAGE="${BMOPATH}/resources/keepalived-docker"

elif [ "${REPO_NAME}" == "ip-address-manager" ]
then
  export IPAMREPO="${UPDATED_REPO}"
  export IPAMBRANCH="${UPDATED_BRANCH}"
  export IPAMPATH="/home/${USER}/tested_repo"
  export IPAM_LOCAL_IMAGE="${IPAMPATH}"

elif [ "${REPO_NAME}" == "ironic-image" ]
then
  export IRONIC_LOCAL_IMAGE="/home/${USER}/tested_repo"
  # Build/test the sushy-tools/vbmc images, since they are defined in this repo
  export SUSHY_TOOLS_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE}/resources/sushy-tools"
  export VBMC_LOCAL_IMAGE="${IRONIC_LOCAL_IMAGE}/resources/vbmc"

elif [ "${REPO_NAME}" == "mariadb-image" ]
then
  export MARIADB_LOCAL_IMAGE="/home/${USER}/tested_repo"

elif [ "${REPO_NAME}" == "ironic-ipa-downloader" ]
then
  export IPA_DOWNLOADER_LOCAL_IMAGE="/home/${USER}/tested_repo"

elif [[ "${REPO_NAME}" == "cluster-api-provider-"* ]]
then
  export CAPM3REPO="${UPDATED_REPO}"
  export CAPM3BRANCH="${UPDATED_BRANCH}"
  export CAPM3PATH="/home/${USER}/tested_repo"
  export CAPM3_LOCAL_IMAGE="${CAPM3PATH}"

elif [[ "${REPO_NAME}" == "project-infra" ]]
then
  if [ "${CAPM3_VERSION}" == "v1alpha4" ]
  then
    export CAPM3_LOCAL_IMAGE_BRANCH="release-0.4"
  elif [ "${CAPM3_VERSION}" == "v1alpha5" ]
  then
    export CAPM3_LOCAL_IMAGE_BRANCH="release-0.5"
  else
    export CAPM3_LOCAL_IMAGE_BRANCH="main"
  fi
fi

export GITHUB_TOKEN

# Ansible colors
export ANSIBLE_FORCE_COLOR=true
# Make 'changed' tasks the same color as 'succeeded' tasks in Jenkins output
export ANSIBLE_COLOR_CHANGED="green"

# Use the IPA which is already downloaded in the image, instead of downloading
# from upstream.
export IPA_DOWNLOAD_ENABLED="false"

METAL3REPO="${METAL3REPO:-https://github.com/metal3-io/metal3-dev-env.git}"
METAL3BRANCH="${METAL3BRANCH:-main}"

# Container image registry value to override the default value in m3-dev-env
# TEMP: Commented out while waiting for nordics registry to come back up.
# export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"registry.nordix.org/quay-io-proxy"}
# export DOCKER_HUB_PROXY=${DOCKER_HUB_PROXY:-"registry.nordix.org/docker-hub-proxy"}
