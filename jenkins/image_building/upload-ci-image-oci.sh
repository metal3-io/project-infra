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

cleanup() {
    rm -f "${OCI_KEY_TMP}"
}
trap cleanup EXIT

img_name="$1"
common_image_name="metal3ci-${IMAGE_OS}-latest"

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

# Delete old image
delete_old_image_from_compute() {
  local image_id
  image_id="$(oci compute image list \
      --compartment-id "${COMPARTMENT_OCID}" \
      --display-name "${common_image_name}" \
      --query 'data[0].id' \
      --raw-output)"

  if [ -n "${image_id}" ] && [ "${image_id}" != "" ]; then
    oci compute image delete \
      --image-id "${image_id}" \
      --force
  fi
}

# Import image from object storage
import_image_from_bucket() {
  oci compute image import from-object \
      --compartment-id "${COMPARTMENT_OCID}" \
      --display-name "${common_image_name}" \
      --namespace "${NAMESPACE_OCID}"\
      --bucket-name "${BUCKET_NAME}" \
      --name "${img_name}".qcow2 \
      --operating-system "Linux" \
      --source-image-type QCOW2 \
      --launch-mode PARAVIRTUALIZED

  # Get image id
  local image_id
  image_id="$(
  oci compute image list \
    --compartment-id "${COMPARTMENT_OCID}" \
    --display-name "${common_image_name}" \
    --sort-by TIMECREATED \
    --sort-order DESC \
    --query 'data[0].id' \
    --raw-output
  )"

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

delete_old_objects() {

  local objects
  mapfile -t objects < <(

    oci os object list \
      --namespace-name "${NAMESPACE_OCID}" \
      --bucket-name "${BUCKET_NAME}" \
      --prefix "metal3ci-${IMAGE_OS}" \
      --query 'data[].name' \
      --raw-output \
    | sort -r
  )

  local retention_num=5

  for ((i="${retention_num}"; i<${#objects[@]}; i++)); do
    oci os object delete \
    --namespace-name "${NAMESPACE_OCID}" \
    --bucket-name "${BUCKET_NAME}" \
    --name "${objects[i]}" \
    --force
    echo "${objects[i]} has been deleted!"
  done
}

install_oci_client
upload_image_to_bucket
delete_old_image_from_compute || true
import_image_from_bucket
delete_old_objects || true
