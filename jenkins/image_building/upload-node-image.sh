#!/usr/bin/env bash

set -ex

rt_delete_artifact() {
    local dst_path="${1:?}"
    curl -s -XDELETE -u"${RT_USER:?}:${RT_TOKEN:?}" "${RT_URL}/${dst_path}"
}

rt_upload_artifact() {
    local src_path="${1:?}"
    local dst_path="${2:?}"
    curl -s -XPUT -u"${RT_USER:?}:${RT_TOKEN:?}" "${RT_URL}/${dst_path}" -T "${src_path}"
}

rt_list_directory() {
    local dst_path="${1:?}"
    curl -s -XGET -u"${RT_USER:?}:${RT_TOKEN:?}" "${RT_URL}/api/storage/${dst_path}"
}

backup_old_image() {
    local dst_path="${1:?}"
    local img_name="${2:?}"

    local tmp_image_name="test.qcow2"

    set +e
    curl -s -f -XGET -u"${RT_USER:?}:${RT_TOKEN:?}" "${RT_URL}/${dst_path}/${img_name}.qcow2" -o "${tmp_image_name}"
    does_file_exist=$?
    set -e

    if [ $does_file_exist -ne 0 ]; then
        return
    fi

    COMMIT_SHORT="$(git rev-parse --short HEAD)"
    NODE_IMAGE_IDENTIFIER="$(date --utc +"%Y%m%dT%H%MZ")_${COMMIT_SHORT}"
    echo "NODE_IMAGE_IDENTIFIER: ${NODE_IMAGE_IDENTIFIER}"

    BACKUP_IMAGE_NAME="${img_name}_${NODE_IMAGE_IDENTIFIER}.qcow2"
    echo "BACKUP_IMAGE_NAME: ${BACKUP_IMAGE_NAME}"
    rt_upload_artifact "${tmp_image_name}" "${dst_path}/${BACKUP_IMAGE_NAME}"
}

upload_node_image() {

    local img_name="${1:?}"

    local rt_folder="metal3/images/k8s_${KUBERNETES_VERSION}"
    local retention_num=5

    backup_old_image "${rt_folder}" "${img_name}"

    RT_URL="${RT_URL:-https://artifactory.nordix.org/artifactory}"

    rt_upload_artifact "${img_name}.qcow2" "${rt_folder}/${img_name}.qcow2"

    # Remove outdated node images, keep n number of latest ones
    # Get list of artifacts into an array and delete those
    mapfile -t < <(rt_list_directory "${rt_folder}" 0 | \
    jq '.children | .[] | .uri' | \
    sort -r |\
    grep "${img_name}_20" | \
    sed -e 's/\"\/\([^"]*\)"/\1/g') 

    for ((i="${retention_num}"; i<${#MAPFILE[@]}; i++)); do
        rt_delete_artifact "${rt_folder}/${MAPFILE[i]}"
        echo "${MAPFILE[i]} has been deleted!"
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    upload_node_image "$@"
fi
