#!/usr/bin/env bash

set -eux

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck disable=SC1091
. "${SCRIPTDIR}"/lib/vars.sh

USER="$(whoami)"
sudo mkdir -p "${IRONIC_DATA_DIR}"
sudo chown -R "${USER}:${USER}" "${IRONIC_DATA_DIR}"


# Download required images for ironic if not already present
# pushd "${IRONIC_DATA_DIR}/html/images"
# wget --no-verbose --no-check-certificate https://artifactory.nordix.org/artifactory/metal3/images/k8s_v1.34.1/CENTOS_9_NODE_IMAGE_K8S_v1.34.1.qcow2
# qemu-img convert -O raw CENTOS_9_NODE_IMAGE_K8S_v1.34.1.qcow2 CENTOS_9_NODE_IMAGE_K8S_v1.34.1-raw.img
# sha256sum "CENTOS_9_NODE_IMAGE_K8S_v1.34.1-raw.img" | awk '{print $1}' > "CENTOS_9_NODE_IMAGE_K8S_v1.34.1-raw.img.sha256sum"
# wget https://artifactory.nordix.org/artifactory/openstack-remote-cache/ironic-python-agent/dib/ipa-centos9-master.tar.gz
# popd

# shellcheck disable=SC1091
source "${SCRIPTDIR}"/lib/ironic_basic_auth.sh
# shellcheck disable=SC1091
source "${SCRIPTDIR}"/lib/ironic_tls_setup.sh

# To bind this into the ironic-client container we need a directory
mkdir -p "${SCRIPTDIR}"/lib/_clouds_yaml
cp "${IRONIC_CACERT_FILE}" "${SCRIPTDIR}"/lib/_clouds_yaml/ironic-ca.crt
yq eval -i '.clouds.metal3.auth.username = env(IRONIC_USERNAME) | .clouds.metal3.auth.password = env(IRONIC_PASSWORD)' "${SCRIPTDIR}"/lib/_clouds_yaml/clouds.yaml

# Create Minikube VM and add correct interfaces
#
init_minikube()
{
    #If the vm exists, it has already been initialized
    if [[ ! "$(sudo virsh list --name --all)" =~ .*(minikube).* ]]; then
        # Loop to ignore minikube issues
        while /bin/true; do
            minikube_error=0
            # This method, defined in lib/common.sh, will either ensure sockets are up'n'running
            # for CS9 and RHEL9, or restart the libvirtd.service for other DISTRO

            #NOTE(elfosardo): workaround for https://bugzilla.redhat.com/show_bug.cgi?id=2057769
            sudo mkdir -p "/etc/qemu/firmware"
            sudo touch "/etc/qemu/firmware/50-edk2-ovmf-amdsev.json"
            sudo su -l -c "minikube start --insecure-registry ${REGISTRY}" "${USER}" || minikube_error=1
            if [[ ${minikube_error} -eq 0 ]]; then
                break
            fi
            sudo su -l -c 'minikube delete --all --purge' "${USER}"
            # NOTE (Mohammed): workaround for https://github.com/kubernetes/minikube/issues/9878
            if ip link show virbr0 > /dev/null 2>&1; then
                sudo ip link delete virbr0
            fi
        done
        sudo su -l -c "minikube stop" "${USER}"
    fi

    MINIKUBE_IFACES="$(sudo virsh domiflist minikube)"

    # The interface doesn't appear in the minikube VM with --live,
    # so just attach it before next boot. As long as the
    # 02_configure_host.sh script does not run, the provisioning network does
    # not exist. Attempting to start Minikube will fail until it is created.
    if ! echo "${MINIKUBE_IFACES}" | grep -w -q provisioning; then
        sudo virsh attach-interface --domain minikube \
            --model virtio --source provisioning \
            --type network --config
    fi

    if ! echo "${MINIKUBE_IFACES}" | grep -w -q external; then
        sudo virsh attach-interface --domain minikube \
            --model virtio --source external \
            --type network --config
    fi
}

# Crete libvirt networks

sudo virsh net-define "${SCRIPTDIR}"/lib/libvirt_network/provisioning.xml
sudo virsh net-define "${SCRIPTDIR}"/lib/libvirt_network/external.xml

sudo virsh net-start provisioning
sudo virsh net-start external

sudo virsh net-autostart provisioning
sudo virsh net-autostart external

# Adding an IP address in the libvirt definition for this network results in
# dnsmasq being run, we don't want that as we have our own dnsmasq, so set
# the IP address here.
# Create a veth iterface peer.
sudo ip link add ironicendpoint type veth peer name ironic-peer
# Create provisioning bridge, if the user allowed bridged provisioning network.
sudo brctl addbr provisioning
# sudo ifconfig provisioning 172.22.0.1 netmask 255.255.255.0 up
# Use ip command. ifconfig commands are deprecated now.
sudo ip link set provisioning up
sudo ip addr add dev ironicendpoint "${BARE_METAL_PROVISIONER_IP}"/"${BARE_METAL_PROVISIONER_CIDR}"
sudo brctl addif provisioning ironic-peer
sudo ip link set ironicendpoint up
sudo ip link set ironic-peer up

# Add physical interfaces to the bridges
sudo brctl addif provisioning eno1
sudo brctl addif external bmext

# Create the external bridge
if ! ip a show external &>/dev/null; then
    sudo brctl addbr external
    # sudo ifconfig external 192.168.111.1 netmask 255.255.255.0 up
    # Use ip command. ifconfig commands are deprecated now.
        sudo ip addr add dev external "${EXTERNAL_SUBNET_V4_HOST}/${EXTERNAL_SUBNET_V4_PREFIX}"
    sudo ip link set external up
fi

minikube config set driver kvm2
minikube config set memory 4096
minikube config set container-runtime containerd
minikube config set cpus 4
minikube config set iso-url file://"${HOME}"/.minikube/cache/iso/minikube-v1.37.0-amd64.iso

init_minikube

# Local registry for images
reg_state=$(sudo "${CONTAINER_RUNTIME}" inspect registry --format "{{.State.Status}}" || echo "error")


if [[ "${reg_state}" == "exited" ]]; then
    sudo "${CONTAINER_RUNTIME}" start registry
elif [[ "${reg_state}" != "running" ]]; then
    sudo "${CONTAINER_RUNTIME}" rm registry -f || true
    sudo "${CONTAINER_RUNTIME}" run -d -p "${REGISTRY}":5000 --name registry docker.io/library/registry:2.7.1
fi
sleep 5

# Start httpd-infra container serve provisioning images for ironic
# shellcheck disable=SC2086
sudo "${CONTAINER_RUNTIME}" run -d --net host --privileged --name httpd-infra \
    -v "${IRONIC_DATA_DIR}":/shared --entrypoint /bin/runhttpd \
    --env "PROVISIONING_INTERFACE=ironicendpoint" "quay.io/metal3-io/ironic"
sleep 5
