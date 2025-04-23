#!/usr/bin/env bash

set -eux

COMMON_IMAGE_NAME="metal3-ci-${IMAGE_OS}-latest"

delete_old_images() {

  # We keep last RETENTION_NUM of metal3ci images and delete old ones when new image has been pushed
  # Example name for metal3ci image: metal3-ci-ubuntu-20240306T0701Z-7b988cb
  RETENTION_NUM=5

  # Delete outdated old images and keep last RETENTION_NUM
  mapfile -t < <(openstack image list -f json | \
    jq .[].Name | \
    sort -r |\
    grep "metal3${IMAGE_TYPE}-${IMAGE_OS}-" | \
    sed 's/"//g')

  for ((i="${RETENTION_NUM}"; i<${#MAPFILE[@]}; i++)); do
    openstack image set "${MAPFILE[i]}" --deactivate
    openstack image delete "${MAPFILE[i]}"
    echo "${MAPFILE[i]} has been deleted!"
  done
}

install_openstack_client() {
  rm -rf venv
  python3 -m venv venv

  # shellcheck source=/dev/null
  . venv/bin/activate
  pip install python-openstackclient==7.0.0
}

# upload_ci_image_xerces uploads an image to OpenStack and names it COMMON_IMAGE_NAME.
# It also renames the existing COMMON_IMAGE_NAME to its original name if it exists.
# Each image has its "original" name stored as the property image_name.
upload_ci_image_xerces() {
  local img_name="$1"
  local common_img_name="${2:-${COMMON_IMAGE_NAME}}"

  qemu-img convert -f qcow2 -O raw "${img_name}".qcow2 "${img_name}".raw
  # Create the new image
  openstack image create "${img_name}" --file "${img_name}".raw --disk-format=raw --property image_name="${img_name}"
  # Rename the image to the common name (and the existing common image to its original name)
  rename_image_common "${img_name}" "${common_img_name}"
}

# rename_image_common renames an image to the COMMON_IMAGE_NAME.
# If the COMMON_IMAGE_NAME already exists, it renames it back to its "original" name.
rename_image_common() {
  local from_name="$1"
  local common_img_name="${2:-${COMMON_IMAGE_NAME}}"

  # Check if the common image already exists
   if openstack image show "${common_img_name}" &>/dev/null; then
     # Get the original name of the current common image
     original_name=$(openstack image show -f json -c properties "${common_img_name}" | jq -r .properties.image_name)
     # Rename the existing common image back to its original name
     openstack image set --name "${original_name}" "${common_img_name}"
   fi
  openstack image set --name "${common_img_name}" "${from_name}"
}

# delete_if_exists deletes an image if it exists in OpenStack.
delete_if_exists() {
  local image_name="$1"
  if openstack image show "${image_name}" &>/dev/null; then
    openstack image set "${image_name}" --deactivate
    openstack image delete "${image_name}"
    echo "${image_name} has been deleted!"
  fi
}

# If the script was run directly (i.e. not sourced), run upload functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_openstack_client
    upload_ci_image_xerces "$@"
fi
