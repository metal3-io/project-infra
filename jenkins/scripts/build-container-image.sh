#!/usr/bin/env bash

# This script is meant to be used by CI, to build and push container images to the container hub.
# However, it can be used by human on a linux environment, with the following requirements:
#  - An existing credentials towards the hub, with push and delete permissions.
#  - Needed tools (git, docker, curl, etc. are installed)

set -eu

set -o pipefail

HUB="${CONTAINER_IMAGE_HUB:-quay.io}"
HUB_ORG="${CONTAINER_IMAGE_HUB_ORG:-metal3-io}"
IMAGE_NAME="${BUILD_CONTAINER_IMAGE_NAME:-${1}}"
REPO_URL="${BUILD_CONTAINER_IMAGE_REPO:-${2}}"
GIT_REFERENCE="${BUILD_CONTAINER_IMAGE_GIT_REFERENCE:-main}"
DOCKERFILE_DIRECTORY="${BUILD_CONTAINER_IMAGE_DOCKERFILE_LOCATION:-/}"
REPO_LOCATION="/tmp/metal3-io"
NEEDED_TOOLS=("git" "curl" "docker" "jq")
__dir__=$(realpath "$(dirname "$0")")

case "${GIT_REFERENCE}" in
  *"refs/heads"*)
    GIT_REFERENCE_TYPE="branch"
    GIT_REFERENCE=$(echo "${GIT_REFERENCE}" | sed 's/refs\/heads\///')
    echo "Detected branch name: ${GIT_REFERENCE}"
    ;;
  *"refs/tags"*)
    GIT_REFERENCE_TYPE="tags"
    GIT_REFERENCE=$(echo "${GIT_REFERENCE}" | sed 's/refs\/tags\///')
    echo "Detected tag name: ${GIT_REFERENCE}"
    ;;
  *)
    GIT_REFERENCE_TYPE="branch"
    echo "No reference type detected. Treating as a branch name: ${GIT_REFERENCE}"
    ;;
esac

check_tools() {
  for tool in "${NEEDED_TOOLS[@]}"; do
    type "${tool}" > /dev/null
  done
}

list_tags() {
  curl -s "https://${HUB}/v2/${HUB_ORG}/${IMAGE_NAME}/tags/list" | jq -r '.tags[]'
}

git_get_current_commit_short_hash() {
  git rev-parse --short HEAD
}

get_date() {
  # Should this be current date, or latest commit date?
  date +%Y%m%d
}

get_image_path() {
  image_tag=${1:?}
  echo "${HUB}/${HUB_ORG}/${IMAGE_NAME}:${image_tag}"
}

build_container_image() {
  image_tag=$(echo "${GIT_REFERENCE}" | sed 's/\//_/')
  image_path=$(get_image_path "${image_tag}")
  echo "Building the image as ${image_path}"
  docker build -t "${image_path}" .
  docker push "${image_path}"
  if [[ "${GIT_REFERENCE_TYPE}" != "branch" ]]; then
    return
  fi
  # If the image was built for a branch, we include some more tags
  declare -a new_image_tags=()
  new_image_tags+=("${GIT_REFERENCE}_$(get_date)_$(git_get_current_commit_short_hash)")
  if [[ "${GIT_REFERENCE}" == "main" ]]; then
    new_image_tags+=("latest")
  fi
  for new_tag in "${new_image_tags[@]}"; do
    new_image_path=$(get_image_path "${new_tag}")
    echo "Tagging the image as ${new_image_path}"
    docker tag "${image_path}" "${new_image_path}"
    docker push "${new_image_path}"
  done
}

build_image() {
  mkdir -p "${REPO_LOCATION}"
  cd "${REPO_LOCATION}"
  rm -rf "${IMAGE_NAME}"
  git clone "${REPO_URL}" "${IMAGE_NAME}"
  cd "${IMAGE_NAME}"
  git checkout "${GIT_REFERENCE}"
  cd "${REPO_LOCATION}/${IMAGE_NAME}${DOCKERFILE_DIRECTORY}"
  build_container_image
}

check_tools
build_image