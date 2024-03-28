#!/bin/bash

set -eu

sudo apt-get update -y
# This script relies on upstream https://github.com/metal3-io/ironic-image/blob/main/patch-image.sh
# to build Ironic container image based on a gerrit refspec of a patch.
# Required parameter is REFSPEC, which is gerrit refspec of the patch
# Example: refs/changes/74/804074/1
IMAGE_REGISTRY="registry.nordix.org"
CONTAINER_IMAGE_REPO="metal3"
IRONIC_REFSPEC="${IRONIC_REFSPEC:-+refs/heads/master:refs/remotes/origin/master}"
IRONIC_INSPECTOR_REFSPEC="${IRONIC_INSPECTOR_REFSPEC:-+refs/heads/master:refs/remotes/origin/master}"
IRONIC_INSPECTOR_REPO="https://opendev.org/openstack/ironic-inspector.git"
IRONIC_REPO="https://opendev.org/openstack/ironic.git"
IRONIC_IMAGE_REPO="https://github.com/metal3-io/ironic-image.git"
IRONIC_IMAGE_REPO_COMMIT="${IRONIC_IMAGE_REPO_COMMIT:-"HEAD"}"
IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH:-"main"}"

# shellcheck disable=SC1091
source "/tmp/harbor_utils.sh"

# Login to the Nordix container registry
docker login "${IMAGE_REGISTRY}" -u "${DOCKER_USER}" -p "${DOCKER_PASSWORD}"

# Gather ironic-inspector commit hash
git clone "${IRONIC_INSPECTOR_REPO}"
pushd "ironic-inspector"
git fetch origin "${IRONIC_INSPECTOR_REFSPEC}"
git checkout FETCH_HEAD
IRONIC_INSPECTOR_COMMIT="$(git rev-parse HEAD)"
popd

# Create a unique tag for Ironic image
git clone ${IRONIC_REPO}
pushd ironic
git fetch "https://review.opendev.org/openstack/ironic" "${IRONIC_REFSPEC}" && git checkout "FETCH_HEAD"
IRONIC_TAG="${IRONIC_TAG:-"$(git rev-parse --short HEAD)"}"
IRONIC_COMMIT="$(git rev-parse HEAD)"
echo "IRONIC_TAG is: ${IRONIC_TAG}"
popd

# We will need this tag while running final deployment test
touch /tmp/vars.sh
cat << EOF > /tmp/vars.sh
IRONIC_TAG="${IRONIC_TAG}"
EOF


# Build & push the Ironic container image
# Push image only if it doesn't already exist in the registry
if docker manifest inspect "${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG}"  > /dev/null; then
    echo "${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG} image already exist -> skipping pushing"
else
    echo "${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG} image does not exist -> going to push to Harbor"
    git clone ${IRONIC_IMAGE_REPO}
    pushd ironic-image
    git checkout "${IRONIC_IMAGE_BRANCH}"
    git checkout "${IRONIC_IMAGE_REPO_COMMIT}"
    IRONIC_IMAGE_REPO_COMMIT="$(git rev-parse HEAD)"

    docker build -t "${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG}" .
    docker push "${IMAGE_REGISTRY}/${CONTAINER_IMAGE_REPO}/ironic-image:${IRONIC_TAG}"
    popd
fi

# Get the digest(s) belonging to the image(s) with the specified tag.
# Only a single digest is expected.
HARBOR_ARTIFACT_DIGEST="$(harbor_get_digests_from_tag "ironic-image" "${IRONIC_TAG}" "false" )"

if (( $(echo "$HARBOR_ARTIFACT_DIGEST" | wc -l) > 1 )); then
    echo "ERROR: There are multiple ironic-image OCI artifacts in Harbor with the ${IRONIC_TAG} tag."
    exit 1
fi

# Logout from the Nordix container registry
docker logout "${IMAGE_REGISTRY}"

# Create Ironic metadata and save it to file
touch /tmp/metadata.txt
cat << EOF > /tmp/metadata.txt
IRONIC_TAG="${IRONIC_TAG}"
IRONIC_REPO="${IRONIC_REPO}"
IRONIC_REFSPEC="${IRONIC_REFSPEC}"
IRONIC_COMMIT="${IRONIC_COMMIT}"
IRONIC_IMAGE_REPO="${IRONIC_IMAGE_REPO}"
IRONIC_IMAGE_REPO_COMMIT="${IRONIC_IMAGE_REPO_COMMIT}"
IRONIC_IMAGE_BRANCH="${IRONIC_IMAGE_BRANCH}"
IRONIC_INSPECTOR_REFSPEC="${IRONIC_INSPECTOR_REFSPEC}"
IRONIC_INSPECTOR_REPO="${IRONIC_INSPECTOR_REPO}"
IRONIC_INSPECTOR_COMMIT="${IRONIC_INSPECTOR_COMMIT}"
IRONIC_IMAGE_HARBOR_DIGEST="${HARBOR_ARTIFACT_DIGEST}"
EOF
