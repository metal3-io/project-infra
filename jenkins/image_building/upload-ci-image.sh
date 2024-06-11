#!/usr/bin/env bash

set -eux

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

upload_ci_image() {

  img_name="$1"

  # Push image to openstack Kna region
  openstack image create "${img_name}" --file "${img_name}".qcow2 --disk-format=qcow2

  # delete old images for Kna region (keeps latest five)
  delete_old_images

  # Push image to openstack xerces region
  export OS_AUTH_URL="https://xerces.ericsson.net:5000"
  openstack image create "${img_name}" --file "${img_name}".qcow2 --disk-format=qcow2

  # delete old images for F region (keeps latest five)
  delete_old_images
}
