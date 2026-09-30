#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/oci-common.sh"

action="${1:-}"
img_name="${2:-}"
if [[ -z "${img_name}" ]]; then
  echo "Missing image name. Usage: $0 [COMMAND] <image-name>"
  exit 1
fi
# "Target object" related env vars specific to node image upload
# These are specifically related to the bucket node-images are stored in
export OCI_CLI_REGION="eu-paris-1"
export COMPARTMENT_OCID=ocid1.compartment.oc1..aaaaaaaadf2menkuy2ovh5bsvwl23vd6tekplacdll3wy64xucnhahm32myq
export BUCKET_NAME=public-metal3-node-image-bucket
export NAMESPACE_OCID=idknxc8t3pjc
export IMAGE_OS="${IMAGE_OS:-unknown}"
export QCOW_IMG_NAME="${img_name}.qcow2"
export SHA_IMG_NAME="${QCOW_IMG_NAME}.sha256"

set -x

# The following functions are only used for this node image upload process
# so they are using global env vars tied to the workflow in certain places
# instead of function args.

# Checks whether a PAR already exists for the given bucket object.
verify_par_for_bucket_object() {
    local object_name="${1:?}"
    oci os preauth-request list \
        --namespace-name "${NAMESPACE_OCID}" \
        --bucket-name "${BUCKET_NAME}" \
        --all | jq -r '.data[]."object-name"' | grep -qx "${object_name}"
}

# Generating PAR for the object/image in the bucket based on the img_name.
# The PAR will have 1 year expiry and will be read-only.
# PAR expiry/rotation/deletion is intentionally out of scope here and is
# handled by a separate workflow.
generate_par_for_bucket_object() {
    local object_name="${1:?}"
    local par_name="${2:?}"
    oci os preauth-request create \
        --namespace-name "${NAMESPACE_OCID}" \
        --bucket-name "${BUCKET_NAME}" \
        --name "${par_name}" \
        --access-type AnyObjectRead \
        --time-expires "$(date -u -d "+1 year" +"%Y-%m-%dT%H:%M:%S.000%:z")" \
        --object-name "${object_name}"
}

# Combines verification and generation, creating a PAR only when
# no PAR exists.
generate_par_for_bucket_object_if_missing() {
    local object_name="${1:?}"
    local par_name="${2:?}"
    if verify_par_for_bucket_object "${object_name}"; then
        echo "PAR for node image ${object_name} (os=${IMAGE_OS}) already exists!"
        return 0
    fi
    generate_par_for_bucket_object "${object_name}" "${par_name}"
}

# Image uploading and PAR management is done by separate users usually,
# thus the two different processes are not combined.
case "${action}" in
  upload-image)
    echo "==> [upload-image] for node image ${img_name} (os=${IMAGE_OS})"
    upload_object_to_bucket "${NAMESPACE_OCID}" "${BUCKET_NAME}" "${QCOW_IMG_NAME}"
    sha256sum "${QCOW_IMG_NAME}" > "${SHA_IMG_NAME}"
    upload_object_to_bucket "${NAMESPACE_OCID}" "${BUCKET_NAME}" "${SHA_IMG_NAME}"
    ;;
  verify-image-par)
    echo "==> [verify-image-par] for node image ${img_name} (os=${IMAGE_OS})"
    verify_par_for_bucket_object "${QCOW_IMG_NAME}"
    ;;
  verify-image-sha-par)
    echo "==> [verify-image-sha-par] for node image ${img_name} (os=${IMAGE_OS})"
    verify_par_for_bucket_object "${SHA_IMG_NAME}"
    ;;
  generate-image-par)
    echo "==> [generate-image-par] for node image ${img_name} (os=${IMAGE_OS})"
    generate_par_for_bucket_object "${QCOW_IMG_NAME}" "${img_name}_qcow2_PAR"
    ;;
  generate-image-sha-par)
    echo "==> [generate-image-sha-par] for node image ${img_name} (os=${IMAGE_OS})"
    generate_par_for_bucket_object "${SHA_IMG_NAME}" "${img_name}_qcow2_sha_PAR"
    ;;
  generate-image-par-if-missing)
    echo "==> [generate-image-par-if-missing] for node image ${img_name} (os=${IMAGE_OS})"
    generate_par_for_bucket_object_if_missing "${QCOW_IMG_NAME}" "${img_name}_qcow2_PAR"
    ;;
  generate-image-sha-par-if-missing)
    echo "==> [generate-image-sha-par-if-missing] for node image ${img_name} (os=${IMAGE_OS})"
    generate_par_for_bucket_object_if_missing "${SHA_IMG_NAME}" "${img_name}_qcow2_sha_PAR"
    ;;
  *)
    echo "Unknown command: ${action}"
    echo "Usage: $0 <upload-image>"
    echo "Usage: $0 <verify-image-par>"
    echo "Usage: $0 <verify-image-sha-par>"
    echo "Usage: $0 <generate-image-par>"
    echo "Usage: $0 <generate-image-sha-par>"
    echo "Usage: $0 <generate-image-par-if-missing>"
    echo "Usage: $0 <generate-image-sha-par-if-missing>"
    exit 1
;;
esac
