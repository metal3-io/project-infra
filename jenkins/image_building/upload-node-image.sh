#!/usr/bin/env bash

set -ex

# Convert a human-readable size (e.g. 1M, 500K) to bytes using IEC binary units.
# Accepts plain integers or suffixed values (K/M/G/T). Uses numfmt when available.
# Falls back to 1048576 (1 MiB) on invalid input.
parse_speed_limit() {
    local value="${1}"
    local default="$(( 1 * 1024 ** 2 ))"

    # Plain integer: use as-is
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        echo "${value}"
        return
    fi

    # Use numfmt if available (handles IEC suffixes: K/M/G/T)
    if command -v numfmt >/dev/null 2>&1; then
        local result
        if result=$(numfmt --from=iec "${value}" 2>/dev/null); then
            echo "${result}"
            return
        fi
    else
        # Manual fallback: integer with K/M/G/T suffix (IEC binary)
        if [[ "${value}" =~ ^([0-9]+)([KkMmGgTt])$ ]]; then
            local num="${BASH_REMATCH[1]}"
            local suffix="${BASH_REMATCH[2]}"
            case "${suffix}" in
                k|K) echo $(( num * 1024 )) ; return ;;
                m|M) echo $(( num * 1024 ** 2 )) ; return ;;
                g|G) echo $(( num * 1024 ** 3 )) ; return ;;
                t|T) echo $(( num * 1024 ** 4 )) ; return ;;
            esac
        fi
    fi

    echo "${default}"
}

# How long curl waits for the initial connection/handshake to succeed (in seconds)
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-60}"

# Aborts the transfer if the speed drops below this limit (in bytes) for the specified duration (in seconds).
# Default speed limit is 1 MiB/s and time is 30 seconds.
CURL_SPEED_LIMIT=$(parse_speed_limit "${CURL_SPEED_LIMIT:-1M}")
CURL_SPEED_TIME="${CURL_SPEED_TIME:-30}"

# How long curl waits before launching a new retry attempt (in seconds)
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-10}"

# Specify the maximum number of retries if the transfer encounters a transient error (like a timeout)
CURL_RETRY="${CURL_RETRY:-999}"

# Set common curl options
CURL_COMMON_OPTS=(
    --connect-timeout "${CURL_CONNECT_TIMEOUT}"
    --speed-limit "${CURL_SPEED_LIMIT}"
    --speed-time "${CURL_SPEED_TIME}"
    --retry-delay "${CURL_RETRY_DELAY}"
    --retry "${CURL_RETRY}"
    --user "${RT_USER:?}:${RT_TOKEN:?}"
    --continue-at -
    --silent
    --show-error
)

rt_delete_artifact() {
    local dst_path="${1:?}"

    curl -XDELETE "${CURL_COMMON_OPTS[@]}" "${RT_URL}/${dst_path}"
}

rt_upload_artifact() {
    local src_path="${1:?}"
    local dst_path="${2:?}"

    curl --fail-with-body -XPUT "${CURL_COMMON_OPTS[@]}" "${RT_URL}/${dst_path}" -T "${src_path}"
}

rt_modify_image() {
    local src_path="${1:?}"
    local dst_path="${2:?}"
    local operation="${3:-copy}"

    # Note! Move operation requires 'Artifactory Pro' license
    curl --fail-with-body \
        -XPOST \
        "${CURL_COMMON_OPTS[@]}" \
        --url "${RT_URL}/api/${operation,,}/${src_path}" \
        --header 'accept: application/json' \
        --data '{"to":"'${dst_path}'", "failFast":1}'
}

rt_list_directory() {
    local dst_path="${1:?}"

    curl -XGET "${CURL_COMMON_OPTS[@]}" "${RT_URL}/api/storage/${dst_path}"
}

purge_tmp_images() {
    local rt_folder="${1:?}"
    local img_name="${2:?}"

    mapfile -t < <(rt_list_directory "${rt_folder}" 0 | \
    jq '.children | .[] | .uri' | \
    sort -r |\
    grep "${img_name}_tmp_" | \
    sed -e 's/\"\/\([^"]*\)"/\1/g')

    for tmp_file in "${MAPFILE[@]}"; do
        rt_delete_artifact "${rt_folder}/${tmp_file}"
        echo "${tmp_file} has been purged!"
    done
}

backup_old_image() {
    local dst_path="${1:?}"
    local img_name="${2:?}"

    mapfile -t < <(rt_list_directory "${dst_path}" 0 | \
    jq '.children | .[] | .uri' | \
    sort -r |\
    grep "${img_name}.qcow2" | \
    sed -e 's/\"\/\([^"]*\)"/\1/g')

    if [[ "${#MAPFILE[@]}" -eq 0 ]]; then
        return
    fi

    COMMIT_SHORT="$(git rev-parse --short HEAD)"
    NODE_IMAGE_IDENTIFIER="$(date --utc +"%Y%m%dT%H%MZ")_${COMMIT_SHORT}"
    echo "NODE_IMAGE_IDENTIFIER: ${NODE_IMAGE_IDENTIFIER}"

    BACKUP_IMAGE_NAME="${img_name}_${NODE_IMAGE_IDENTIFIER}.qcow2"
    echo "BACKUP_IMAGE_NAME: ${BACKUP_IMAGE_NAME}"

    rt_modify_image "${RT_URL}/${dst_path}/${img_name}.qcow2" "${dst_path}/${BACKUP_IMAGE_NAME}"
}

upload_node_image() {
    local img_name="${1:?}"
    local rt_folder="metal3/images/k8s_${KUBERNETES_VERSION}"
    local retention_num=5
    local tmp_name="${img_name}_tmp_$(date --utc +"%Y%m%dT%H%MZ").qcow2"

    RT_URL="${RT_URL:-https://artifactory.nordix.org/artifactory}"

    # Purge any temp files left behind from previous runs
    purge_tmp_images "${rt_folder}" "${img_name}"

    # Upload the name image with a temp name and replace the current image
    rt_upload_artifact "${img_name}.qcow2" "${rt_folder}/${tmp_name}"
    backup_old_image "${rt_folder}" "${img_name}"
    rt_modify_image "${rt_folder}/${tmp_name}" "${rt_folder}/${img_name}.qcow2" "copy"

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

# If the script was run directly (i.e. not sourced), run the upload_node_image func
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    upload_node_image "$@"
fi
