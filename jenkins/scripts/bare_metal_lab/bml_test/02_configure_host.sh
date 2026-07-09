#!/usr/bin/env bash

set -eux

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

K8S_VERSION="${K8S_VERSION:-v1.36.0}"
IMAGE_OS="${IMAGE_OS:-CENTOS_10}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-bml}"
KIND_NODE_NAME="${KIND_CLUSTER_NAME}-control-plane"
KIND_PROVISIONING_NETWORK="${KIND_PROVISIONING_NETWORK:-bml-provisioning}"
KIND_EXTERNAL_NETWORK="${KIND_EXTERNAL_NETWORK:-bml-external}"
PROVISIONING_SUBNET_V4_GATEWAY="${PROVISIONING_SUBNET_V4_GATEWAY:-172.22.0.254}"
KIND_PROVISIONING_GATEWAY="${KIND_PROVISIONING_GATEWAY:-${PROVISIONING_SUBNET_V4_GATEWAY}}"
KIND_EXTERNAL_GATEWAY="${KIND_EXTERNAL_GATEWAY:-${EXTERNAL_SUBNET_V4_HOST}}"
EXTERNAL_IFACE="${EXTERNAL_IFACE:-bmext}"

USER="$(whoami)"
sudo mkdir -p "${IRONIC_DATA_DIR}/html/images"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"


# Download required images for ironic if not already present
pushd "${IRONIC_DATA_DIR}/html/images"
wget --no-check-certificate -q "https://artifactory.nordix.org/artifactory/metal3/images/k8s_${K8S_VERSION}/${IMAGE_OS}_NODE_IMAGE_K8S_${K8S_VERSION}.qcow2"
qemu-img convert -O raw "${IMAGE_OS}_NODE_IMAGE_K8S_${K8S_VERSION}.qcow2" "${IMAGE_OS}_NODE_IMAGE_K8S_${K8S_VERSION}-raw.img"
sha256sum "${IMAGE_OS}_NODE_IMAGE_K8S_${K8S_VERSION}-raw.img" | awk '{print $1}' > "${IMAGE_OS}_NODE_IMAGE_K8S_${K8S_VERSION}-raw.img.sha256sum"
wget -q https://artifactory.nordix.org/artifactory/openstack-remote/ironic-python-agent/dib/ipa-centos9-master.tar.gz
popd

# shellcheck disable=SC1091
source "${SCRIPTDIR}"/lib/ironic_basic_auth.sh
# shellcheck disable=SC1091
source "${SCRIPTDIR}"/lib/ironic_tls_setup.sh

# To bind this into the ironic-client container we need a directory
mkdir -p "${SCRIPTDIR}"/lib/_clouds_yaml
cp "${IRONIC_CACERT_FILE}" "${SCRIPTDIR}"/lib/_clouds_yaml/ironic-ca.crt
yq eval -i '.clouds.metal3.auth.username = env(IRONIC_USERNAME) | .clouds.metal3.auth.password = env(IRONIC_PASSWORD)' "${SCRIPTDIR}"/lib/_clouds_yaml/clouds.yaml

# Create the bootstrap kind cluster if it does not already exist.
ensure_kind_cluster()
{
    if sudo su -l -c "kind get clusters | grep -Fxq '${KIND_CLUSTER_NAME}'" "${USER}"; then
        return
    fi

    cat << EOF > "/tmp/kind-${KIND_CLUSTER_NAME}.yaml"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
nodes:
  - role: control-plane
EOF

    sudo su -l -c "kind create cluster --name \"${KIND_CLUSTER_NAME}\" --config \"/tmp/kind-${KIND_CLUSTER_NAME}.yaml\"" "${USER}"
    rm -f "/tmp/kind-${KIND_CLUSTER_NAME}.yaml"
}

# Create a Docker network bound to an existing Linux bridge.
ensure_docker_network_on_bridge()
{
    local network_name="$1"
    local bridge_name="$2"
    local subnet="$3"
    local gateway="$4"

    if sudo docker network inspect "${network_name}" > /dev/null 2>&1; then
        return
    fi

    sudo docker network create \
        --driver bridge \
        --subnet "${subnet}" \
        --gateway "${gateway}" \
        -o com.docker.network.bridge.name="${bridge_name}" \
        "${network_name}"
}

    # Attach the kind control-plane container to a given Docker network with a fixed IP.
connect_kind_node_network()
{
    local network_name="$1"
    local ip_addr="$2"

    if sudo docker inspect -f '{{json .NetworkSettings.Networks}}' "${KIND_NODE_NAME}" | grep -q "\"${network_name}\""; then
        return
    fi

    sudo docker network connect --ip "${ip_addr}" "${network_name}" "${KIND_NODE_NAME}"
}

# Ensure the provisioning/external Docker networks are present and mapped to bridges.
configure_kind_networks()
{
    ensure_docker_network_on_bridge "${KIND_PROVISIONING_NETWORK}" provisioning "172.22.0.0/24" "${KIND_PROVISIONING_GATEWAY}"
    ensure_docker_network_on_bridge "${KIND_EXTERNAL_NETWORK}" external "192.168.111.0/24" "${KIND_EXTERNAL_GATEWAY}"
}

# Ensure a bridge has the expected IPv4 address.
ensure_bridge_has_ip()
{
    local bridge_name="$1"
    local ip_cidr="$2"

    if ! ip -4 addr show dev "${bridge_name}" | grep -q "${ip_cidr}"; then
        sudo ip addr add dev "${bridge_name}" "${ip_cidr}"
    fi
}

# Ensure an interface is enslaved to the expected bridge.
ensure_bridge_member()
{
    local bridge_name="$1"
    local iface_name="$2"

    if ! ip -o link show "${iface_name}" | grep -q "master ${bridge_name}"; then
        sudo brctl addif "${bridge_name}" "${iface_name}"
    fi
}

# Resolve and validate the external host interface used by the external bridge.
resolve_external_iface()
{
    if ! ip link show "${EXTERNAL_IFACE}" > /dev/null 2>&1; then
        echo "Configured EXTERNAL_IFACE '${EXTERNAL_IFACE}' does not exist" >&2
        exit 1
    fi

    sudo ip link set "${EXTERNAL_IFACE}" up
    echo "${EXTERNAL_IFACE}"
}

# Ensure host forwarding/NAT rules exist for external subnet internet egress.
ensure_host_egress_for_external_subnet()
{
    local external_subnet="192.168.111.0/24"
    local default_if

    default_if="$(ip route show default | awk '/default/ {print $5; exit}')"
    if [[ -z "${default_if}" ]]; then
        echo "Unable to discover host default route interface for internet egress" >&2
        exit 1
    fi

    if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
        echo "Host prerequisite missing: net.ipv4.ip_forward must be 1" >&2
        exit 1
    fi

    sudo iptables -t nat -C POSTROUTING -s "${external_subnet}" -o "${default_if}" -j MASQUERADE || \
        sudo iptables -t nat -A POSTROUTING -s "${external_subnet}" -o "${default_if}" -j MASQUERADE
    sudo iptables -C FORWARD -i external -o "${default_if}" -j ACCEPT || \
        sudo iptables -A FORWARD -i external -o "${default_if}" -j ACCEPT
    sudo iptables -C FORWARD -i "${default_if}" -o external -m state --state RELATED,ESTABLISHED -j ACCEPT || \
        sudo iptables -A FORWARD -i "${default_if}" -o external -m state --state RELATED,ESTABLISHED -j ACCEPT
}

# Fail fast if external bridge does not own the expected gateway IP.
validate_external_gateway_binding()
{
    if ! ip -4 addr show dev external | grep -q "${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}"; then
        echo "External gateway ${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX} is not bound to bridge 'external'" >&2
        exit 1
    fi
}

# Ensure Docker network gateway and bridge gateway use the same IP.
validate_external_gateway_consistency()
{
    if [[ "${KIND_EXTERNAL_GATEWAY}" != "${EXTERNAL_SUBNET_V4_HOST}" ]]; then
        echo "Gateway mismatch: KIND_EXTERNAL_GATEWAY=${KIND_EXTERNAL_GATEWAY}, expected ${EXTERNAL_SUBNET_V4_HOST}" >&2
        exit 1
    fi
}

# Ensure provisioning gateway is also controlled by a single canonical value.
validate_provisioning_gateway_consistency()
{
    if [[ "${KIND_PROVISIONING_GATEWAY}" != "${PROVISIONING_SUBNET_V4_GATEWAY}" ]]; then
        echo "Gateway mismatch: KIND_PROVISIONING_GATEWAY=${KIND_PROVISIONING_GATEWAY}, expected ${PROVISIONING_SUBNET_V4_GATEWAY}" >&2
        exit 1
    fi
}

# Adding an IP address in the libvirt definition for this network results in
# dnsmasq being run, we don't want that as we have our own dnsmasq, so set
# the IP address here.
# Create a veth iterface peer.
if ! ip link show ironicendpoint > /dev/null 2>&1; then
    sudo ip link add ironicendpoint type veth peer name ironic-peer
fi
# Create provisioning bridge, if the user allowed bridged provisioning network.
if ! ip a show provisioning &>/dev/null; then
    sudo brctl addbr provisioning
fi
# sudo ifconfig provisioning 172.22.0.1 netmask 255.255.255.0 up
# Use ip command. ifconfig commands are deprecated now.
sudo ip link set provisioning up
if ! ip -4 addr show dev ironicendpoint | grep -q "${BARE_METAL_PROVISIONER_IP}/${BARE_METAL_PROVISIONER_CIDR}"; then
    sudo ip addr add dev ironicendpoint "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}"
fi
if ! ip -o link show ironic-peer | grep -q "master provisioning"; then
    sudo brctl addif provisioning ironic-peer
fi
sudo ip link set ironicendpoint up
sudo ip link set ironic-peer up

# Create the external bridge
if ! ip a show external &>/dev/null; then
    sudo brctl addbr external
fi
sudo ip link set external up
ensure_bridge_has_ip external "${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}"

# Add physical interfaces to the bridges
ensure_bridge_member provisioning eno1
ensure_bridge_member external "$(resolve_external_iface)"
validate_external_gateway_binding
validate_external_gateway_consistency
validate_provisioning_gateway_consistency
ensure_host_egress_for_external_subnet

ensure_kind_cluster
configure_kind_networks
connect_kind_node_network "${KIND_PROVISIONING_NETWORK}" "172.22.0.9"
connect_kind_node_network "${KIND_EXTERNAL_NETWORK}" "192.168.111.9"

# Local registry for images
reg_state=$(sudo "${CONTAINER_RUNTIME}" inspect registry --format "{{.State.Status}}" || echo "error")


if [[ "${reg_state}" == "exited" ]]; then
    sudo "${CONTAINER_RUNTIME}" start registry
elif [[ "${reg_state}" != "running" ]]; then
    sudo "${CONTAINER_RUNTIME}" rm registry -f || true
    sudo "${CONTAINER_RUNTIME}" run -d -p 5000:5000 --name registry docker.io/library/registry:2.7.1
fi
sleep 5

# Start httpd-infra container serve provisioning images for ironic
# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd-infra \
    -v "${IRONIC_DATA_DIR}":/shared --entrypoint /bin/runhttpd \
    --env "PROVISIONING_INTERFACE=ironicendpoint" "quay.io/metal3-io/ironic"
sleep 5
