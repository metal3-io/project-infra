#!/usr/bin/env bash

set -eux

OCI_KEY_TMP="/tmp/oci_key.pem"

set +x

cp "${OCI_KEY_FILE}" "${OCI_KEY_TMP}"
chmod 600 "${OCI_KEY_TMP}"

export OCI_CLI_KEY_FILE="${OCI_KEY_TMP}"
export OCI_CLI_USER="${OCI_CLI_USER}"
export OCI_CLI_TENANCY="${OCI_CLI_TENANCY}"
export OCI_CLI_FINGERPRINT="${OCI_CLI_FINGERPRINT}"

set -x

export OCI_CLI_REGION="eu-paris-1"
export COMPARTMENT_OCID=ocid1.tenancy.oc1..aaaaaaaalbjclmsqx5zyjbqgtywhfxns4qavoppuhp6peixiqmm6vu3qyn7a
export BUCKET_NAME=ImageStorage
export NAMESPACE_OCID=idknxc8t3pjc
export IMAGE_OS="${IMAGE_OS}"

COMMON_IMAGE_NAME="metal3ci-${IMAGE_OS}-latest"
CANDIDATE_IMAGE_NAME="metal3ci-${IMAGE_OS}-staging"

cleanup() {
    rm -f "${OCI_KEY_TMP}"
}
trap cleanup EXIT

action="${1:-}"
img_name="${2:-}"

install_oci_client() {
  rm -rf venv
  python3 -m venv venv

  # shellcheck source=/dev/null
  . venv/bin/activate
  # Install OCI CLI
  pip install oci-cli==3.76.0
}

# Upload image to object storage
upload_image_to_bucket() {

  oci os object put \
      --namespace-name "${NAMESPACE_OCID}" \
      --bucket-name "${BUCKET_NAME}" \
      --name "${img_name}".qcow2 \
      --file "${img_name}".qcow2
}

# Delete image by display name if present
delete_image_from_compute_by_name() {
  local image_name="$1"
  local image_id
  image_id="$(oci compute image list \
      --compartment-id "${COMPARTMENT_OCID}" \
      --display-name "${image_name}" \
      --query 'data[0].id' \
      --raw-output)"

  if [ -n "${image_id}" ] && [ "${image_id}" != "" ]; then
    oci compute image delete \
      --image-id "${image_id}" \
      --force
  fi
}

get_image_id_by_name() {
  local image_name="$1"
  oci compute image list \
    --compartment-id "${COMPARTMENT_OCID}" \
    --display-name "${image_name}" \
    --sort-by TIMECREATED \
    --sort-order DESC \
    --query 'data[0].id' \
    --raw-output
}

wait_for_image_available() {
  local image_id="$1"
  local state

  while true; do
    state="$(
      oci compute image get \
        --image-id "${image_id}" \
        --query 'data."lifecycle-state"' \
        --raw-output
    )"

    echo "Image state: ${state}"

    case "${state}" in
      AVAILABLE)
        break
        ;;
      IMPORTING|PROVISIONING)
        sleep 20
        ;;
      *)
        echo "Image ended in unexpected state: ${state}"
        exit 1
        ;;
    esac
  done
}

# Import image from object storage as OCI candidate image
import_candidate_image_from_bucket() {
  oci compute image import from-object \
      --compartment-id "${COMPARTMENT_OCID}" \
      --display-name "${CANDIDATE_IMAGE_NAME}" \
      --namespace "${NAMESPACE_OCID}"\
      --bucket-name "${BUCKET_NAME}" \
      --name "${img_name}".qcow2 \
      --operating-system "Linux" \
      --source-image-type QCOW2 \
      --launch-mode PARAVIRTUALIZED

  local image_id
  image_id="$(get_image_id_by_name "${CANDIDATE_IMAGE_NAME}")"
  wait_for_image_available "${image_id}"
}

# Rename an image's display name by id.
rename_image() {
  local image_id="$1"
  local new_name="$2"

  oci compute image update \
    --image-id "${image_id}" \
    --display-name "${new_name}" \
    --force
}

# Promote the candidate image "latest" display name.
promote_candidate_to_latest() {
  local candidate_image_id
  candidate_image_id="$(get_image_id_by_name "${CANDIDATE_IMAGE_NAME}")"

  if [[ -z "${candidate_image_id}" || "${candidate_image_id}" == "null" ]]; then
    echo "Candidate image ${CANDIDATE_IMAGE_NAME} not found"
    exit 1
  fi

  wait_for_image_available "${candidate_image_id}"

  # Capture the current "latest" image (if any) so we can preserve it.
  local old_latest_id
  old_latest_id="$(get_image_id_by_name "${COMMON_IMAGE_NAME}")"

  local backup_name=""
  if [[ -n "${old_latest_id}" && "${old_latest_id}" != "null" ]]; then
    backup_name="${COMMON_IMAGE_NAME}-backup-$(date -u +%Y%m%d%H%M%S)"
    echo "==> [promote-candidate] preserving current '${COMMON_IMAGE_NAME}' as '${backup_name}'"
    # Free up the "latest" display name without destroying the image.
    rename_image "${old_latest_id}" "${backup_name}"
  else
    echo "==> [promote-candidate] no existing '${COMMON_IMAGE_NAME}' image found"
  fi

  # Promote the candidate to "latest". On failure, roll the old image back so
  # dependent jobs always have a working "latest".
  echo "==> [promote-candidate] promoting candidate to '${COMMON_IMAGE_NAME}'"
  if ! rename_image "${candidate_image_id}" "${COMMON_IMAGE_NAME}"; then
    echo "ERROR: failed to promote candidate to '${COMMON_IMAGE_NAME}'" >&2
    if [[ -n "${backup_name}" && -n "${old_latest_id}" && "${old_latest_id}" != "null" ]]; then
      echo "==> [promote-candidate] rolling back '${backup_name}' to '${COMMON_IMAGE_NAME}'" >&2
      rename_image "${old_latest_id}" "${COMMON_IMAGE_NAME}"
    fi
    exit 1
  fi

  # Promotion succeeded; now it is safe to delete the preserved old image.
  if [[ -n "${old_latest_id}" && "${old_latest_id}" != "null" ]]; then
    echo "==> [promote-candidate] deleting preserved old image '${backup_name}'"
    if ! oci compute image delete --image-id "${old_latest_id}" --force; then
      echo "WARNING: failed to delete old image '${backup_name}' (${old_latest_id})" >&2
    fi
  fi

  echo "==> [promote-candidate] DONE"
}

# Delete a bucket object by name.
delete_bucket_object() {
  local object_name="$1"

  if oci os object delete \
      --namespace-name "${NAMESPACE_OCID}" \
      --bucket-name "${BUCKET_NAME}" \
      --name "${object_name}" \
      --force; then
    echo "Deleted bucket object: ${object_name}"
  else
    echo "WARNING: failed to delete bucket object: ${object_name}" >&2
  fi
}

install_oci_client

case "${action}" in
  upload-candidate)
    if [[ -z "${img_name}" ]]; then
      echo "Missing image name. Usage: $0 upload-candidate <image-name>"
      exit 1
    fi
    echo "==> [upload-candidate] START for ${img_name} (os=${IMAGE_OS})"
    upload_image_to_bucket
    echo "==> [upload-candidate] deleting existing candidate image '${CANDIDATE_IMAGE_NAME}' if present"
    delete_image_from_compute_by_name "${CANDIDATE_IMAGE_NAME}" || true
    echo "==> [upload-candidate] importing candidate image '${CANDIDATE_IMAGE_NAME}'"
    import_candidate_image_from_bucket
    echo "==> [upload-candidate] removing intermediate bucket object '${img_name}.qcow2'"
    delete_bucket_object "${img_name}".qcow2 || true
    echo "==> [upload-candidate] DONE"
    ;;
  promote-candidate)
    promote_candidate_to_latest
    ;;
  *)
    echo "Unknown action: ${action}"
    echo "Usage: $0 <upload-candidate|promote-candidate> [image-name]"
    exit 1
    ;;
esac
