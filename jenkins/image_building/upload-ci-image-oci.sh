#!/usr/bin/env bash

set -eu

img_name="$1"
common_image_name="metal3ci-${IMAGE_OS}-latest"

install_oci_client() {
  rm -rf venv
  python3 -m venv venv

  # shellcheck source=/dev/null
  . venv/bin/activate
  # Install OCI CLI
  pip install oci-cli
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
  oci compute image delete \
    --image-id "$(oci compute image list \
      --compartment-id "${COMPARTMENT_OCID}" \
      --display-name "${common_image_name}" \
      --query 'data[0].id' \
      --raw-output)" \
    --force
}

# Import image from obect storage
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
}

delete_old_objects() {
  mapfile -t < <(
    oci os object list \
      --namespace-name "${NAMESPACE_OCID}" \
      --bucket-name "${BUCKET_NAME}" \
      --prefix "metal3ci-${IMAGE_OS}" \
      --query 'data[].name' \
      --raw-output \
    | sort
  )

  RETENTION_NUM=5

  for ((i="${RETENTION_NUM}"; i<${#MAPFILE[@]}; i++)); do
    oci os object delete \
    --namespace-name "${NAMESPACE_OCID}" \
    --bucket-name "${BUCKET_NAME}" \
    --name "${MAPFILE[i]}" \
    --force
    echo "${MAPFILE[i]} has been deleted!"
  done
}

install_oci_client
upload_image_to_bucket
delete_old_image_from_compute || true
import_image_from_bucket
delete_old_objects || true
