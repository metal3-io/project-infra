#! /usr/bin/env bash

# Description:
# Extract IP from CIDR
#
# Example:
#   Input: "10.0.10.0/24"
#   Output: "10.0.10.0"
#
get_ip_from_cidr() {
  echo "${1:?}" | cut -d'/' -f1
}

# Description:
# Extract Prefix from CIDR
#
# Example:
#   Input: "10.0.10.0/24"
#   Output: "24"
#
get_prefix_from_cidr() {
  echo "${1:?}" | cut -d'/' -f2
}

# Description:
# Get N-th IP after given IP
#
# Example:
#   Input: "10.0.10.0" 15
#   Output: "10.0.10.15"
#
get_nth_ip(){
  local IP INCREMENT IP_HEX NEXT_IP_HEX NEXT_IP

  IP="${1:?}"
  INCREMENT="${2:-1}"
  # shellcheck disable=SC2183
  # shellcheck disable=SC2086
  IP_HEX="$(printf '%.2X%.2X%.2X%.2X\n' ${IP//./ })"
  NEXT_IP_HEX="$(printf %.8X "$(( 0x${IP_HEX} + INCREMENT ))")"
  # shellcheck disable=SC2183
  # shellcheck disable=SC2046
  NEXT_IP="$(printf '%d.%d.%d.%d\n' $(echo "${NEXT_IP_HEX}" | sed -r 's/(..)/0x\1 /g') )"
  echo "${NEXT_IP}"
}

# Description:
# Get Gateway IP address from CIDR.
# In our scenario we always define 1st IP in
# CIDR as Gateway.
#
# Example:
#   Input: "10.0.10.0/24"
#   Output: "10.0.10.1"
#
get_gateway_ip_from_cidr() {
  get_nth_ip "$(get_ip_from_cidr "${1:?}")" 1
}

# Description:
# Generates random string of given size.
#
# Usage:
#   get_random_string <string_length>
#
get_random_string() {
  local STR_LENGTH

  STR_LENGTH="${1:?}"

  tr -cd 'a-f0-9' < /dev/urandom | head -c "${STR_LENGTH}"
}

# Description:
# Renders cloud init user data template and outputs to given file
#
# Usage:
#   render_user_data <ssh_authorized_pub_key> <ssh_user> <in_template> <out_file>
#
render_user_data() {

  local IN_FILE OUT_FILE

  export USERDATA_SSH_AUTHORIZED_KEY="${1:?}"
  export USERDATA_SSH_USER="${2:?}"
  export USERDATA_SSH_USER_GROUP="${3:?}"
  export USERDATA_HOSTNAME="${4:?}"
  IN_FILE="${5:?}"
  OUT_FILE="${6:?}"

  envsubst < "${IN_FILE}" > "${OUT_FILE}"
}

# Description:
# Generates subnet name from Network name.
#
# Example:
#   Input: "metal3-network"
#   Output: "metal3-network-subnet"
#
get_subnet_name() {
  echo "${1:?}-subnet"
}

# Description:
# Generates External Port name from Network name.
#
# Example:
#   Input: "metal3-network"
#   Output: "metal3-network-ext-port"
#
get_external_port_name() {
  echo "${1:?}-ext-port"
}

# Description:
# Get resource id from name.
#
# Usage: get_resource_id_from_name <resource_type> <resource_name>
#
get_resource_id_from_name() {
  local RESOURCE_TYPE RESOURCE_NAME RESOURCE_INFO

  RESOURCE_TYPE="${1:?}"
  RESOURCE_NAME="${2:?}"

  # Get Rsource Info
  # shellcheck disable=SC2086
  RESOURCE_INFO="$(openstack ${RESOURCE_TYPE} show "${RESOURCE_NAME}" -f json)"

  [[ -z "${RESOURCE_INFO}" ]] && return

  # Output list of IDs
  echo "${RESOURCE_INFO}" | jq -r '.id'
}


# Description:
# Returns a list of all ports in
# an openstack subnet
#
# Usage: get_ports_in_subnet <subnet_name_or_id>
#
get_ports_in_subnet() {
  local SUBNET PORT_LIST

  SUBNET="${1:?}"

  # Get Port List
  PORT_LIST="$(openstack port list --fixed-ip subnet="${SUBNET}" -f json)"

  [[ -z "${PORT_LIST}" ]] && return

  # Output list of IDs
  echo "${PORT_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"'
}

# Description:
# Returns a list of all subnet in
# an openstack network
#
# Usage: get_subnets_in_network <network_name_or_id>
#
get_subnets_in_network() {
  local NET SUBNET_LIST

  NET="${1:?}"

  # Get Port List
  SUBNET_LIST="$(openstack subnet list --network "${NET}" -f json)"

  [[ -z "${SUBNET_LIST}" ]] && return

  # Output list of IDs
  echo "${SUBNET_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"'
}

# Description:
# Deletes an openstack port.
#
# Usage: delete_port <port_name_or_id>
#
delete_port() {
  local PORT PORT_INFO DEVICE_OWNER DEVICE_ID

  PORT="${1:?}"

  # Get port info
  PORT_INFO="$(openstack port show -f json "${PORT}" || true)"

  [[ -z "${PORT_INFO}" ]] && return

  # Get device info
  DEVICE_OWNER="$(echo "${PORT_INFO}" | jq -r '.device_owner')"


  # if connected to router then disconnect from router
  if [[ "${DEVICE_OWNER}" = *router* ]]
  then
    DEVICE_ID="$(echo "${PORT_INFO}" | jq -r '.device_id')"
    echo "deleting port ${PORT} from device ${DEVICE_ID}"
    openstack router remove port "${DEVICE_ID}" "${PORT}" > /dev/null
  else
    # delete port
    echo "deleting port ${PORT}"
    openstack port delete "${PORT}" > /dev/null
  fi
}

# Description:
# Deletes an openstack subnet. It deletes
# all associated ports before deleting the subnet.
#
# Usage: delete_subnet <subnet_name_or_id>
#
delete_subnet() {
  local SUBNET SUBNET_INFO PORTS

  SUBNET="${1:?}"

  # Get Subnet info
  SUBNET_INFO="$(openstack subnet show -f json "${SUBNET}" || true)"

  [[ -z "${SUBNET_INFO}" ]] && return

  # Get all ports in this subnet
  PORTS="$(get_ports_in_subnet "${SUBNET}")"

  # Delete ports
  for PORT in ${PORTS}
  do
    delete_port "${PORT}"
  done

  # delete subnet
  echo "deleting subnet ${SUBNET}"
  openstack subnet delete "${SUBNET}" > /dev/null
}

# Description:
# Deletes an openstack network. Deletes
# any associated subnets and ports before
# deleting network. If the network is deleted by
# name then there can be multiple networks
# by that name. This function will delete all
# the networks by that name and their associated
# subnets and ports.
#
# Usage: delete_port <network_name_or_id>
#
delete_network() {
  local NET NET_LIST_ALL JQ_QUERY NET_LIST NET_ARRAY NET_INFO SUBNETS

  NET="${1:?}"

  # Get list of networks with name
  NET_LIST_ALL="$(openstack network list -f json || true)"
  JQ_QUERY="map(select((.Name | contains(\"${NET}\")) or (.ID | contains(\"${NET}\"))))"
  NET_LIST="$(echo "${NET_LIST_ALL}" | jq "${JQ_QUERY}")"
  NET_ARRAY="$(echo "${NET_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"')"

  for NET_ID in ${NET_ARRAY}
  do
    # Get Subnet info
    NET_INFO="$(openstack network show -f json "${NET_ID}" || true)"

    [[ -z "${NET_INFO}" ]] && return

    # Get list of subnet IDs in this network
    SUBNETS="$(get_subnets_in_network "${NET_ID}")"

    # Delete subnets
    for SUBNET in ${SUBNETS}
    do
      delete_subnet "${SUBNET}"
    done

    # delete network
    echo "deleting network ${NET_ID}"
    openstack network delete "${NET_ID}" > /dev/null
  done
}

# Description:
# Creates a network and a default subnet.
# If IS_EXTERNAL is 1 then also sets a gateway
# for subnet
#
# Usage:
#   create_network_and_subnet <cidr> <is_external:0/1> <network_name>
#
create_network_and_subnet() {

  local CIDR NET_NAME SUBNET_NAME NET_INFO
  local GATEWAY_IP START_IP END_IP NET_ID
  local SUBNET_INFO SUBNET_ID

  CIDR="${1:?}"
  NET_NAME="${3:?}"

  SUBNET_NAME="$(get_subnet_name "${NET_NAME}")"
  GATEWAY_IP="$(get_gateway_ip_from_cidr "${CIDR}")"
  START_IP="$(get_nth_ip "${GATEWAY_IP}" 9)"
  END_IP="$(get_nth_ip "${GATEWAY_IP}" 199)"

  NET_INFO="$(openstack network create -f json\
    --enable \
    --description "${NET_NAME}" \
    --enable-port-security \
    "${NET_NAME}")"

  NET_ID="$(echo "${NET_INFO}" | jq -r '.id')"

  SUBNET_CMD="openstack subnet create -f json\
    --subnet-range ${CIDR} \
    --dhcp \
    --ip-version 4 \
    --network ${NET_ID} \
    --gateway ${GATEWAY_IP} \
    --allocation-pool start=${START_IP},end=${END_IP} \
    ${SUBNET_NAME}"

  SUBNET_INFO="$(eval "${SUBNET_CMD}")"
  SUBNET_ID="$(echo "${SUBNET_INFO}" | jq -r '.id')"

  echo "${NET_ID}" "${SUBNET_ID}"
}

# Description:
# Creates a network and attaches it to router for
# external connectivity.
#
# Usage:
#   create_external_net <cidr> <router_name_or_id> <network_name>
#
create_external_net() {
  local CIDR NET_NAME SUBNET_NAME ROUTER PORT_NAME
  local GATEWAY_IP NET_INFO NET_ID SUBNET_ID PORT_INFO PORT_ID

  CIDR="${1:?}"
  ROUTER="${2:?}"
  NET_NAME="${3:?}"

  SUBNET_NAME="$(get_subnet_name "${NET_NAME}")"
  PORT_NAME="$(get_external_port_name "${NET_NAME}")"
  GATEWAY_IP="$(get_gateway_ip_from_cidr "${CIDR}")"

  NET_INFO="$(create_network_and_subnet "${CIDR}" "${NET_NAME}")"

  NET_ID="$(echo "${NET_INFO}" | cut -d' ' -f1)"
  SUBNET_ID="$(echo "${NET_INFO}" | cut -d' ' -f2)"

  # Create external Port
  PORT_INFO="$(openstack port create -f json \
    --network "${NET_ID}" \
    --fixed-ip subnet="${SUBNET_ID}",ip-address="${GATEWAY_IP}" \
    "${PORT_NAME}")"

  PORT_ID="$(echo "${PORT_INFO}" | jq -r '.id')"

  # Attach port to router
  openstack router add port "${ROUTER}" "${PORT_ID}" > /dev/null
}

# Description:
# Creates a Router and attaches it to external gateway.
#
# Usage:
#   create_router <external_network> <router_name>
#
create_router() {
  local CIDR NET_NAME SUBNET_NAME ROUTER PORT_NAME
  local GATEWAY_IP NET_INFO NET_ID SUBNET_ID

  EXT_NET="${1:?}"
  ROUTER_NAME="${2:?}"

  ROUTER_INFO="$(openstack router create -f json\
    --enable \
    --description "${ROUTER_NAME}" \
    --ha \
    "${ROUTER_NAME}")"

  ROUTER_ID="$(echo "${ROUTER_INFO}" | jq -r '.id')"

  openstack router set --external-gateway "${EXT_NET}" "${ROUTER_ID}" > /dev/null
}

# Description:
# Deletes a Router and any associated ports attached to it.
#
# Usage:
#   delete_router <router_name>
#
delete_router() {
  local ROUTER_LIST_ALL JQ_QUERY ROUTER_LIST ROUTER_ARRAY
  local ROUTER_NAME ROUTER_INFO ROUTER_ID ROUTER_PORT_INFO ROUTER_PORT_ID_LIST

  ROUTER_NAME="${1:?}"

  # Get list of networks with name
  ROUTER_LIST_ALL="$(openstack router list -f json || true)"
  JQ_QUERY="map(select((.Name | contains(\"${ROUTER_NAME}\")) or (.ID | contains(\"${ROUTER_NAME}\"))))"
  ROUTER_LIST="$(echo "${ROUTER_LIST_ALL}" | jq "${JQ_QUERY}")"
  ROUTER_ARRAY="$(echo "${ROUTER_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"')"

  for ROUTER_ID in ${ROUTER_ARRAY}
  do
    ROUTER_INFO="$(openstack router show "${ROUTER_ID}" -f json)"

    [[ -z "${ROUTER_INFO}" ]] && return

    ROUTER_PORT_INFO="$(echo "${ROUTER_INFO}" | jq -r '.interfaces_info')"
    ROUTER_PORT_ID_LIST="$(echo "${ROUTER_PORT_INFO}" \
      | sed 's@\\@@g' \
      | jq -r 'map(.port_id) | @csv' \
      | tr ',' '\n' \
      | tr -d '"')"

    for PORT in ${ROUTER_PORT_ID_LIST}
    do
      delete_port "${PORT}"
    done

    openstack router delete "${ROUTER_ID}" > /dev/null
  done
}

# Description:
# Creates Openstack SSH keypair.
#
# Usage:
#   create_keypair <public_key_file> <keypair_name>
#
create_keypair() {
  local PUBLIC_KEY KEYPAIR_NAME

  PUBLIC_KEY="${1:?}"
  KEYPAIR_NAME="${2:?}"

  openstack keypair create -f json \
    --public-key "${PUBLIC_KEY}" \
    "${KEYPAIR_NAME}" > /dev/null
}

# Description:
# Deletes Openstack SSH keypair.
#
# Usage:
#   delete_keypair <keypair_name>
#
delete_keypair() {
  local KEYPAIR_NAME

  KEYPAIR_NAME="${1:?}"

  openstack keypair delete "${KEYPAIR_NAME}" > /dev/null 2>&1 || true
}

# Description:
# Remove old image with changes the name of the new image
#
# Usage:
#   replace_image <src_image_name> <dst_image_name>
#
replace_image() {
  local SRC_IMAGE DST_IMAGE IMAGE_LIST IMAGE_ARRAY IMAGE_ID

  SRC_IMAGE="${1:?}"
  DST_IMAGE="${2:?}"


  # Get list of images by name
  IMAGE_LIST="$(openstack image list --name "${DST_IMAGE}" -f json || true)"
  IMAGE_ARRAY="$(echo "${IMAGE_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"')"

  for IMAGE_ID in ${IMAGE_ARRAY}
  do
    echo "Deleting image ${IMAGE_ID}"
    openstack image set "${IMAGE_ID}" --deactivate
    openstack image delete "${IMAGE_ID}" 
  done

  echo "Setting image name from ${SRC_IMAGE} to ${DST_IMAGE}"
  openstack image set --name "${DST_IMAGE}" "${SRC_IMAGE}"
}

# Description:
# backups old image with and saves new image
#
# Usage:
#   backup_and_replace_image <new_image_name> <old_image_name>
#
backup_and_replace_image() {
  local NEW_IMAGE OLD_IMAGE IMAGE_IDENTIFIER

  RETENTION_NUM=5
  NEW_IMAGE="${1:?}"
  OLD_IMAGE="${2:?}"

  #Backup old image by setting new name with identifier
  # We keep last 5 of metal3 backup images
  # Example name for backup metal3 image: metal3-ci-centos-metal3-img-20230918T0916Z
  IMAGE_IDENTIFIER="$(date --utc +"%Y%m%dT%H%MZ")"
  openstack image set --name "${OLD_IMAGE}" "${OLD_IMAGE}-${IMAGE_IDENTIFIER}"

  # Delete outdated old images and keep last RETENTION_NUM
  mapfile -t < <(openstack image list  -f json | \
    jq .[].Name | \
    sort -r |\
    grep "metal3-ci-centos-metal3-img-" | \
    sed 's/"//g')

  for ((i="${RETENTION_NUM}"; i<${#MAPFILE[@]}; i++)); do
    openstack image set "${MAPFILE[i]}" --deactivate
    openstack image delete "${MAPFILE[i]}" 
    echo "${MAPFILE[i]} has been deleted!"
  done

  echo "Setting image name from ${NEW_IMAGE} to ${OLD_IMAGE}"
  openstack image set --name "${NEW_IMAGE}" "${OLD_IMAGE}"
}

# Description:
# deletes Openstack image.
#
# Usage:
#   delete_image <image_name>
#
delete_image() {
  local IMAGE_NAME

  IMAGE_NAME="${1:?}"
  
  openstack image delete "${IMAGE_NAME}" > /dev/null
}

# Description:
# Creates Openstack volume.
#
# Usage:
#   create_volume <source_image_name> <volume_size> <builder_volume_name>
#
create_volume() {
  local SOURCE_IMAGE_NAME VOLUME_SIZE BUILDER_VOLUME_NAME

  SOURCE_IMAGE_NAME="${1:?}"
  VOLUME_SIZE="${2:?}"
  BUILDER_VOLUME_NAME="${3:?}"
  
  openstack volume create \
    --image "${SOURCE_IMAGE_NAME}" \
    --size "${VOLUME_SIZE}" \
    --bootable \
    "${BUILDER_VOLUME_NAME}"
}

# Description:
# Remove old volume with changes the name of the new volume
#
# Usage:
#   replace_volume <src_volume_name> <dst_volume_name>
#
replace_volume() {
  local SRC_VOLUME DST_VOLUME VOLUME_LIST VOLUME_ARRAY VOLUME_ID

  SRC_VOLUME="${1:?}"
  DST_VOLUME="${2:?}"


  # Get list of volumes by name
  VOLUME_LIST="$(openstack volume list --name "${DST_VOLUME}" -f json || true)"
  VOLUME_ARRAY="$(echo "${VOLUME_LIST}" | jq -r 'map(.ID) | @csv' | tr ',' '\n' | tr -d '"')"

  for VOLUME_ID in ${VOLUME_ARRAY}
  do
    echo "Deleting volume ${VOLUME_ID}"
    openstack volume delete "${VOLUME_ID}" > /dev/null
  done

  echo "Setting volume name from ${SRC_VOLUME} to ${DST_VOLUME}"
  openstack volume set --name "${DST_VOLUME}" "${SRC_VOLUME}" > /dev/null
}

# Description:
# Waits for SSH connection to come up for a server
#
# Usage:
#   wait_for_ssh <ssh_user> <ssh_key_path> <server>
#
wait_for_ssh() {
  local USER KEY SERVER

  USER="${1:?}"
  KEY="${2:?}"
  SERVER="${3:?}"

  echo "Waiting for SSH connection to Host[${SERVER}]"
  until ssh -o ConnectTimeout=2 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "${KEY}" \
    "${USER}"@"${SERVER}" echo "SSH to host is up" > /dev/null 2>&1
        do sleep 1
  done

  echo "SSH connection to host[${SERVER}] is up."
}

# Description:
# Deletes an openstack security group.
#
# Usage: delete_sg <sg_name_or_id>
#
delete_sg() {
  local SG

  SG="${1:?}"

  openstack security group delete "${SG}" > /dev/null 2>&1 || true
}

# Description:
# Shares image beween projects.
#
# Usage share_image <IMAGE_ID> <PROJECT_ID>
share_image() {
  local PROJECT_ID IMAGE_ID

  IMAGE_ID="${1:?}"
  PROJECT_ID="${2:?}"

  openstack image set --shared "${IMAGE_ID}"
  openstack image add project "${IMAGE_ID}" "${PROJECT_ID}" > /dev/null 2>&1 || true
}

# Description:
# Accepts shared image.
#
# Usage accept_shared_image <IMAGE_ID>
accept_shared_image() {
  local IMAGE_ID

  IMAGE_ID="${1:?}"
  openstack image set --accept "${IMAGE_ID}"
}

# Description:
# Gets Project ID by Project Name.
#
# Usage get_project_id <PROJECT_NAME>

get_project_id() {
  local PROJECT_NAME

  PROJECT_NAME="${1:?}"
  openstack project list  -f json | jq -r --arg projectName "${PROJECT_NAME}" '.[] | select(.Name == $projectName ).ID'
}

# Description:
# Gets IMAGE ID by IMAGE Name.
#
# Usage get_image_id <IMAGE_NAME>
get_image_id() {
  local IMAGE_NAME

  IMAGE_NAME="${1:?}"
  openstack image show "$IMAGE_NAME" -f json | jq -r '.id'
}